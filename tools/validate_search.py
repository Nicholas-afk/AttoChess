#!/usr/bin/env python3
"""Validate the persistent-search build using Unicorn 2.1.4 and NASM.

Usage: python3 tools/validate_search.py
Creates proof/search-regression.json. No external DOS installation
is required. The 274-byte control adds the search fix without shrinking the
pawn predicate; it is the differential oracle for the new 272-byte build.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import random
import subprocess
import sys
import tempfile

import unicorn
from unicorn import Uc, UC_ARCH_X86, UC_MODE_16, UC_HOOK_INTR
from unicorn.x86_const import (
    UC_X86_REG_AX, UC_X86_REG_BP, UC_X86_REG_CS, UC_X86_REG_CX,
    UC_X86_REG_DI, UC_X86_REG_DS, UC_X86_REG_DX, UC_X86_REG_EFLAGS,
    UC_X86_REG_ES, UC_X86_REG_IP, UC_X86_REG_SP, UC_X86_REG_SS,
)

HERE = Path(__file__).resolve().parent.parent
BASE = 0x10000
BOARD_SIZE = 156
ENTRY = 0x15B  # Unchanged MOVE_SUB entry; checked against NASM listing.
LIMIT = 100_000_000
CELLS = (0, 9, 0x2E, 13, 10, 0xA2, 0xA3, 0xA5, 0xA6, 0xA7,
         0x24, 0x14, 0x92, 0x93, 0x95, 0x96, 0x97)
PIECES = {'N': 0x92, 'B': 0x93, 'P': 0x14, 'Q': 0x95, 'R': 0x96,
          'K': 0x97, 'n': 0xA2, 'b': 0xA3, 'p': 0x24, 'q': 0xA5,
          'r': 0xA6, 'k': 0xA7}
OPENINGS = [f'{f}2{f}{r}' for f in 'abcdefgh' for r in '34'] + [
    'b1a3', 'b1c3', 'g1f3', 'g1h3', 'e2e4g1f3', 'd2d4c2c4', 'b1c3e2e3']


def square(s: str) -> int:
    return (10 - int(s[1])) * 12 + 4 + ord(s[0]) - ord('a')


def coordinate(index: int) -> str:
    row, col = divmod(index, 12)
    assert 2 <= row <= 9 and 4 <= col <= 11, index
    return chr(ord('a') + col - 4) + str(10 - row)


def signed(n: int) -> int:
    return (n + 128) % 256 - 128


def machine(image: bytes) -> Uc:
    m = Uc(UC_ARCH_X86, UC_MODE_16)
    m.mem_map(0, 0x200000)
    m.mem_write(BASE + 0x100, image)
    for reg in (UC_X86_REG_CS, UC_X86_REG_DS, UC_X86_REG_ES, UC_X86_REG_SS):
        m.reg_write(reg, 0x1000)
    m.reg_write(UC_X86_REG_SP, 0xFFFE)
    m.reg_write(UC_X86_REG_EFLAGS, 2)
    return m


def run_game(image: bytes, moves: str, position: bytes | None = None) -> dict:
    """Run real input/output flow; inject a fixture only at the first input."""
    m = machine(image)
    pending = list(moves.encode('ascii'))
    events = []
    exhausted = False
    injected = False
    board_at = BASE + 0x100 + len(image)

    def interrupt(uc, vector, _):
        nonlocal exhausted, injected
        ax = uc.reg_read(UC_X86_REG_AX)
        if vector == 0x29:
            events.append(('out', ax & 255))
        elif vector == 0x21 and ax >> 8 == 1:
            if position is not None and not injected:
                uc.mem_write(board_at, position)
                injected = True
            if not pending:
                exhausted = True
                uc.emu_stop()
                return
            value = pending.pop(0)
            events.append(('echo', value))
            uc.reg_write(UC_X86_REG_AX, (ax & 0xFF00) | value)
        else:
            raise AssertionError(f'unexpected interrupt {vector:x}, AX={ax:x}')

    m.hook_add(UC_HOOK_INTR, interrupt)
    m.emu_start(BASE + 0x100, BASE + 0x10000, count=LIMIT)
    return {'events': events, 'board': bytes(m.mem_read(board_at, BOARD_SIZE)),
            'input_boundary': exhausted, 'ip': m.reg_read(UC_X86_REG_IP)}


def fixture(template: bytes, pieces: dict[str, str]) -> bytes:
    board = bytearray(template)
    for r in '12345678':
        for f in 'abcdefgh':
            board[square(f+r)] = 0
    for sq, piece in pieces.items():
        board[square(sq)] = PIECES[piece]
    return bytes(board)


def search(image: bytes, board: bytes, depth: int = 4) -> dict:
    """Call MOVE_SUB after a dummy white move outside the scanned board."""
    m = machine(image)
    board_offset = 0x100 + len(image)
    m.mem_write(BASE + board_offset, board)
    for reg, value in ((UC_X86_REG_SP, 0xFFFC), (UC_X86_REG_BP, 0x500),
                       (UC_X86_REG_DI, 0x501), (UC_X86_REG_CX, depth),
                       (UC_X86_REG_DX, 0x1828)):
        m.reg_write(reg, value)
    m.mem_write(BASE + 0xFFFC, b'\x00\x60')
    m.mem_write(BASE + 0x500, b'\x14\x00')
    m.emu_start(BASE + ENTRY, BASE + 0x6000, count=LIMIT)
    assert m.reg_read(UC_X86_REG_IP) == 0x6000, \
        f'search stopped at IP={m.reg_read(UC_X86_REG_IP):04x}'
    # Speculative moves must all be undone.
    assert bytes(m.mem_read(BASE + board_offset, BOARD_SIZE)) == board
    bp = m.reg_read(UC_X86_REG_BP) - board_offset
    di = m.reg_read(UC_X86_REG_DI) - board_offset
    selected = (bp, di) if 0 <= bp < BOARD_SIZE and board[bp] else None
    return {'move': selected, 'best_score': signed(m.reg_read(UC_X86_REG_AX) >> 8),
            'returned_score': signed(m.reg_read(UC_X86_REG_AX) & 255)}


def generated_moves(board: bytes, black: bool):
    """Independent reduced-rule move generator, using row/column geometry.

    As in AttoChess, no castling, promotion, check legality, en passant, or
    generated double pawn pushes. Human input remains trusted by the engine.
    """
    for r in range(8):
        for c in range(8):
            src = (r+2)*12+c+4
            piece = board[src]
            if not piece or bool(piece & 0x20) != black:
                continue
            kind = piece & 7
            if kind == 4:
                step = 1 if black else -1
                targets = [(step, 0), (step, -1), (step, 1)]
            elif kind == 2:
                targets = [(a,b) for a,b in ((1,2),(2,1),(-1,2),(-2,1),
                                            (1,-2),(2,-1),(-1,-2),(-2,-1))]
            else:
                targets = []
                if kind in (3,5,7):
                    targets += [(1,1),(1,-1),(-1,1),(-1,-1)]
                if kind in (5,6,7):
                    targets += [(1,0),(-1,0),(0,1),(0,-1)]
            for dr, dc in targets:
                nr, nc = r+dr, c+dc
                while 0 <= nr < 8 and 0 <= nc < 8:
                    dst = (nr+2)*12+nc+4
                    target = board[dst]
                    if target and bool(target & 0x20) == black:
                        break
                    if kind != 4 or bool(target) == bool(dc):
                        yield src, dst
                    if target or kind in (2,4,7):
                        break
                    nr += dr
                    nc += dc


def main():
    original = (HERE / 'legacy/ATTOCHES-272-zero-floor.COM').read_bytes()
    assert hashlib.sha256(original).hexdigest() == \
        '02b80d2b11ba3c6bea02b112e7009c318aac35b3e869f8bb823dc2aa6cdd6f8e'
    candidate = (HERE / 'ATTOCHES.COM').read_bytes()
    source = (HERE / 'AttoChess.asm').read_text()
    with tempfile.TemporaryDirectory() as temp:
        temp = Path(temp)
        rebuilt = temp / 'candidate.com'
        subprocess.run(['nasm', '-f', 'bin', '-w+error', '-o', str(rebuilt),
                        str(HERE / 'AttoChess.asm')], check=True)
        assert rebuilt.read_bytes() == candidate and len(candidate) == 272
        needle = '    neg ah\n    rcl al, 1'
        assert source.count(needle) == 1
        control_source = source.replace(needle,
            '    and ah, dl\n    neg ah\n    rcl al, 1')
        (temp / 'control.asm').write_text(control_source)
        subprocess.run(['nasm', '-f', 'bin', '-w+error', '-o',
                        str(temp / 'control.com'), str(temp / 'control.asm')], check=True)
        control = (temp / 'control.com').read_bytes()
    assert len(control) == 274
    cases = 0
    for dl, dh in ((0x18,0x28), (0x28,0x18)):
        for captured in CELLS:
            if captured & dh:
                continue
            for vector in range(256):
                old_cf = bool(captured & dl)
                new_cf = bool(captured)
                old_test = (((vector << 1) | old_cf) & 3).bit_count() % 2 == 0
                new_test = (((vector << 1) | new_cf) & 3).bit_count() % 2 == 0
                assert old_cf == new_cf and old_test == new_test
                cases += 1
    print(f'PASS: {cases} pawn predicate cases', flush=True)

    template = run_game(candidate, '')['board']
    assert template == run_game(original, '')['board']
    opening_results = []
    for moves in OPENINGS:
        a = run_game(candidate, moves)
        b = run_game(control, moves)
        assert a['input_boundary'] and b['input_boundary'], moves
        assert a['events'] == b['events'] and a['board'] == b['board'], moves
        opening_results.append(moves)
        print(f'PASS: 272/274-byte control comparison {moves}', flush=True)

    before = fixture(template, {'h8':'k', 'a7':'p', 'b5':'Q', 'h1':'K'})
    after = fixture(template, {'h8':'k', 'a7':'p', 'a5':'Q', 'h1':'K'})
    old = run_game(original, 'b5a5', before)
    new = run_game(candidate, 'b5a5', before)
    assert not old['input_boundary'] and old['ip'] == 0x162
    assert new['input_boundary']
    old_search, new_search = search(original, after), search(candidate, after)
    assert old_search['move'] is None
    assert new_search['move'] in set(generated_moves(after, True))
    assert new_search['best_score'] == -1
    chosen = ''.join(coordinate(i) for i in new_search['move'])
    assert chosen == 'a7a6'
    assert new['board'][square('a6')] == PIECES['p']
    assert new['board'][square('a7')] == 0
    print(f'PASS: old release stops; candidate plays {chosen} at score -1', flush=True)

    rng = random.Random(272)
    random_results = []
    squares = [f+r for f in 'abcdefgh' for r in '12345678']
    for index in range(100):
        pieces = ['k','K'] + rng.choices(['p','n','b','r','q','P','N','B','R','Q'],
                                      k=rng.randrange(0,5))
        placement = dict(zip(rng.sample(squares, len(pieces)), pieces))
        board = fixture(template, placement)
        legal = set(generated_moves(board, True))
        try:
            a, b = search(candidate, board, 3), search(control, board, 3)
        except AssertionError as error:
            raise AssertionError((index, placement, str(error))) from error
        assert a == b, (index, placement, a, b)
        assert (a['move'] in legal) if legal else (a['move'] is None), \
            (index, placement, a)
        random_results.append({'pieces':placement, 'generated_moves':len(legal),
            'selected': ''.join(coordinate(i) for i in a['move']) if a['move'] else None,
            'best_score':a['best_score']})
    print('PASS: 100 seeded synthetic positions at depth 3; selected moves and board undo', flush=True)
    report = {
        'original_sha256':hashlib.sha256(original).hexdigest(),
        'candidate_sha256':hashlib.sha256(candidate).hexdigest(),
        'candidate_bytes':len(candidate), 'source_rebuild_identical':True,
        'emulator':unicorn.__version__,
        'pawn_predicate_cases':cases,
        'control_bytes':len(control), 'control_comparisons':opening_results,
        'resignation_regression':{
            'fen_before':'7k/p7/8/1Q6/8/8/8/7K w - - 0 1',
            'human_move':'b5a5', 'original_stops_at':'0x162',
            'candidate_move':chosen, 'candidate_best_score':-1,
            'candidate_reaches_next_input':True},
        'synthetic_depth':3, 'synthetic_positions':random_results,
        'limitations':[
            'Synthetic positions obey the board alphabet, not full FIDE legality.',
            'The control compares the pawn optimization, not old/new search equivalence.',
            'Unicorn models DOS I/O with register preservation.',
            'No claim of increased playing strength or full chess legality.',
            'Original release proof evidence does not certify the changed search.'],
        'passed':True,
    }
    (HERE / 'proof/search-regression.json').write_text(json.dumps(report, indent=2, sort_keys=True)+'\n')


if __name__ == '__main__':
    main()
