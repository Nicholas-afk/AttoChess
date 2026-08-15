#!/usr/bin/env python3
"""Differentially execute the original and optimized AttoChess COM images.

This is an independent regression oracle, not the formal proof.  It executes
real 16-bit instructions in Unicorn, supplies DOS INT 21h/AH=01h input, models
INT 29h output, and compares event traces plus the relocated 156-byte board at
the next input boundary.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from dataclasses import dataclass
from pathlib import Path

import unicorn
from unicorn import UC_ARCH_X86, UC_HOOK_INTR, UC_MODE_16, Uc, UcError
from unicorn.x86_const import (
    UC_X86_REG_AX,
    UC_X86_REG_CS,
    UC_X86_REG_DS,
    UC_X86_REG_ES,
    UC_X86_REG_IP,
    UC_X86_REG_SP,
    UC_X86_REG_SS,
)


SEGMENT = 0x1000
PHYSICAL_BASE = SEGMENT << 4
IMAGE_ADDRESS = PHYSICAL_BASE + 0x100
MEMORY_SIZE = 0x200000
BOARD_BYTES = 13 * 12
# The 272-byte artifact intentionally overlaps eval_db[7] (2Eh) with the
# first hidden top-border fill byte.  Offsets 4..11 are neither displayed nor
# scanned as sources; 2Eh and 09h both reject every move under both color masks.
REPRESENTATION_ONLY_OFFSETS = frozenset(range(4, 12))
MAX_INSTRUCTIONS = 100_000_000
OPENING_MOVES = [
    "a2a3", "a2a4", "b2b3", "b2b4", "c2c3", "c2c4", "d2d3", "d2d4",
    "e2e3", "e2e4", "f2f3", "f2f4", "g2g3", "g2g4", "h2h3", "h2h4",
    "b1a3", "b1c3", "g1f3", "g1h3",
]
MULTI_TURN_MOVES = ["e2e4g1f3", "d2d4c2c4", "b1c3e2e3"]


@dataclass(frozen=True)
class Run:
    events: tuple[tuple[str, int], ...]
    board: bytes
    exhausted_input: bool
    final_ax: int
    final_ip: int


def execute(image: bytes, board_offset: int, move: bytes) -> Run:
    machine = Uc(UC_ARCH_X86, UC_MODE_16)
    machine.mem_map(0, MEMORY_SIZE)
    machine.mem_write(IMAGE_ADDRESS, image)
    for register in (UC_X86_REG_CS, UC_X86_REG_DS, UC_X86_REG_ES, UC_X86_REG_SS):
        machine.reg_write(register, SEGMENT)
    machine.reg_write(UC_X86_REG_IP, 0x100)
    machine.reg_write(UC_X86_REG_SP, 0xFFFE)

    pending = list(move)
    events: list[tuple[str, int]] = []
    exhausted = False

    def interrupt(uc: Uc, vector: int, _user: object) -> None:
        nonlocal exhausted
        ax = uc.reg_read(UC_X86_REG_AX) & 0xFFFF
        if vector == 0x29:
            events.append(("out", ax & 0xFF))
            return
        if vector == 0x21 and (ax >> 8) == 0x01:
            if not pending:
                exhausted = True
                uc.emu_stop()
                return
            value = pending.pop(0)
            events.append(("echo", value))
            uc.reg_write(UC_X86_REG_AX, (ax & 0xFF00) | value)
            return
        raise RuntimeError(f"unsupported DOS interrupt {vector:02x} with AX={ax:04x}")

    machine.hook_add(UC_HOOK_INTR, interrupt)
    try:
        machine.emu_start(
            IMAGE_ADDRESS,
            PHYSICAL_BASE + 0x10000,
            count=MAX_INSTRUCTIONS,
        )
    except UcError as error:
        raise RuntimeError(f"Unicorn execution failed: {error}") from error

    board_address = PHYSICAL_BASE + board_offset
    board = bytes(machine.mem_read(board_address, BOARD_BYTES))
    return Run(
        events=tuple(events),
        board=board,
        exhausted_input=exhausted,
        final_ax=machine.reg_read(UC_X86_REG_AX) & 0xFFFF,
        final_ip=machine.reg_read(UC_X86_REG_IP) & 0xFFFF,
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("original", type=Path)
    parser.add_argument("optimized", type=Path)
    parser.add_argument(
        "--json-report",
        type=Path,
        help="write a machine-readable record of the completed comparisons",
    )
    parser.add_argument(
        "--canonical-suite",
        action="store_true",
        help="run the audited 20-opening plus three multi-turn suite",
    )
    parser.add_argument(
        "moves",
        nargs="*",
    )
    args = parser.parse_args()
    if args.canonical_suite and args.moves:
        parser.error("--canonical-suite cannot be combined with explicit moves")
    moves = OPENING_MOVES + MULTI_TURN_MOVES if args.canonical_suite else args.moves
    if not moves:
        moves = OPENING_MOVES

    original = args.original.read_bytes()
    optimized = args.optimized.read_bytes()
    if len(original) != 276:
        raise SystemExit(f"expected 276-byte original, got {len(original)}")
    if len(optimized) >= len(original):
        raise SystemExit("optimized image is not smaller")

    print(
        f"original={len(original)} sha256={hashlib.sha256(original).hexdigest()}"
    )
    print(
        f"optimized={len(optimized)} sha256={hashlib.sha256(optimized).hexdigest()}"
    )

    completed: list[dict[str, object]] = []
    for move_text in moves:
        move = move_text.encode("ascii")
        if not move or len(move) % 4:
            raise SystemExit(
                f"input must contain one or more four-character moves: {move_text!r}"
            )
        reference = execute(original, 0x0214, move)
        candidate = execute(optimized, 0x0100 + len(optimized), move)
        if not reference.exhausted_input or not candidate.exhausted_input:
            raise SystemExit(f"execution did not reach the next input boundary for {move_text}")
        if reference.events != candidate.events:
            raise SystemExit(
                f"observable event mismatch for {move_text}: "
                f"{len(reference.events)} vs {len(candidate.events)} events"
            )
        if any(
            left != right and index not in REPRESENTATION_ONLY_OFFSETS
            for index, (left, right) in enumerate(zip(reference.board, candidate.board))
        ):
            differing = [
                index
                for index, (left, right) in enumerate(zip(reference.board, candidate.board))
                if left != right and index not in REPRESENTATION_ONLY_OFFSETS
            ]
            raise SystemExit(
                f"board mismatch for {move_text} at relative offsets {differing[:16]}"
            )
        print(
            f"PASS {move_text}: events={len(reference.events)} "
            f"board_sha256={hashlib.sha256(reference.board).hexdigest()}"
        )
        completed.append(
            {
                "input": move_text,
                "events": len(reference.events),
                "event_trace_sha256": hashlib.sha256(repr(reference.events).encode()).hexdigest(),
                "original_board_sha256": hashlib.sha256(reference.board).hexdigest(),
                "optimized_board_sha256": hashlib.sha256(candidate.board).hexdigest(),
                "matched_except_offsets": sorted(REPRESENTATION_ONLY_OFFSETS),
            }
        )

    print(f"PASS: {len(moves)} complete differential input sequences")
    if args.json_report is not None:
        report = {
            "schema": 1,
            "emulator": {"name": "unicorn", "version": unicorn.__version__},
            "original": {
                "file": args.original.name,
                "bytes": len(original),
                "sha256": hashlib.sha256(original).hexdigest(),
                "board_offset": 0x0214,
            },
            "optimized": {
                "file": args.optimized.name,
                "bytes": len(optimized),
                "sha256": hashlib.sha256(optimized).hexdigest(),
                "board_offset": 0x0100 + len(optimized),
            },
            "interrupt_model": {
                "input": "INT 21h/AH=01h returns AL and preserves AH",
                "output": "INT 29h observes AL and preserves modeled registers",
            },
            "instruction_limit_per_sequence": MAX_INSTRUCTIONS,
            "representation_only_offsets": sorted(REPRESENTATION_ONLY_OFFSETS),
            "passed": True,
            "sequences": completed,
        }
        args.json_report.write_text(
            json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
        print(f"report={args.json_report}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
