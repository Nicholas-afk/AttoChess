# AttoChess

**AttoChess is the world's smallest x86 chess program: a complete, playable
16-bit DOS chess engine in 272 bytes with a real four-ply search.**

AttoChess is a size-optimized descendant of Dmitry Shechtman's
[LeanChess](https://github.com/leanchess/leanchess.github.io). It initializes
and draws its own board, reads a move, searches four plies recursively, chooses
a reply, updates the position, and repeats. The entire executable—including
code and tables—is 272 bytes.

[Play it in the browser](https://nicholas-afk.github.io/AttoChess/) ·
[Download the COM](ATTOCHES.COM) · [Read the source](AttoChess.asm) ·
[Inspect the proof evidence](proof/README.md)

| Program | Bytes | Year | Author | Platform |
|---|---:|---:|---|---|
| 1K ZX Chess | 672 | 1982 | David Horne | Sinclair ZX81 |
| BootChess | 487 | 2015 | Olivier Poudade | x86 boot sector |
| Toledo Atomchess | 352 | 2015 | Óscar Toledo G. | x86 DOS `.COM` |
| Toledo Atomchess, HACK build | 326 | 2019 | Óscar Toledo G. | x86 DOS `.COM` |
| LeanChess | 288 | 2019 | Dmitry Shechtman | x86 DOS `.COM` |
| AttoChess, previous release | 276 | 2026 | Nicholas Tanner | x86 DOS `.COM` |
| **AttoChess, current release** | **272** | **2026** | **Nicholas Tanner** | **x86 DOS `.COM`** |

The current build is 16 bytes below LeanChess and four bytes below the previous
AttoChess release. Toledo Atomchess is listed twice because its 352-byte form is
the one usually cited, while its stripped HACK build from December 2019 reached
326 and is the smallest size it ever attained on x86.

## Reproduce the 272-byte image

The current source uses NASM syntax and targets the Intel 80186 instruction
set. NASM 3.02 produced the release build, and the image is byte-identical
under NASM 2.16.01.

```sh
nasm -f bin -w+error -o ATTOCHES.COM AttoChess.asm
wc -c ATTOCHES.COM
shasum -a 256 AttoChess.asm ATTOCHES.COM
```

Expected output:

```text
272 ATTOCHES.COM
2dda33f61b4d1665f01138cbaf78f79636eabd71017abbc77efdaac13e807400  AttoChess.asm
02b80d2b11ba3c6bea02b112e7009c318aac35b3e869f8bb823dc2aa6cdd6f8e  ATTOCHES.COM
```

The checked-in [NASM listing](AttoChess.lst) and
[16-bit disassembly](AttoChess.ndisasm) provide independent byte-level views.
The exact 276-byte predecessor remains under [`legacy/`](legacy/README.md).

## Run it

AttoChess runs under DOSBox, PCem, 86Box, DOS on real hardware, or another
environment implementing the DOS interrupts it uses.

```text
mount c: .
c:
ATTOCHES.COM
```

You play White. Enter four characters—source square followed immediately by
destination square:

```text
e2e4
```

The computer calculates Black's reply and redraws the board.

## The four new bytes

The 272-byte release adds four compositionally checked one-byte reductions to
the 276-byte program. The fourth depends on the second freeing `BH`; these are
not four unrelated patches.

### 1. Test the exchanged source — minus one byte

The old prologue compared the source to `CH`, then cleared `AX` and exchanged
the source into `AL`. Search depths are 0–4, so `CH=0`. The new sequence first
performs the exchange and tests the value already in `AL`:

```asm
; before
cmp  [bp], ch
jz   $
xor  ax, ax
xchg al, [bp]

; after
xor  ax, ax
xchg al, [bp]
test al, al
jz   $
```

On a nonempty source the continuing state is identical. On an empty source the
new store writes zero over zero before entering the same deliberate self-loop.

### 2. Encode pawn occupancy in parity — minus one byte net

The predicate maps destination occupancy into carry, rotates it beside vector
parity, and lets `TEST` set `PF` exactly when the two bits agree:

```asm
push ax
and  ah, dl
neg  ah
rcl  al, 1
test al, 3
pop  ax
jpo  vec_cont
```

`POP` restores `AX` without changing flags. This leaves the captured byte in
`AH`, so undo can use `XCHG AH,[DI]` and the old two-byte `MOV BH,AH` clone
disappears. The predicate grows by one byte while the clone loses two.

### 3. Overlap evaluation and initialization data — minus one byte

The king value `eval_db[7] = 2Eh` is also the first hidden top-border fill
byte. Both `09h` and `2Eh` block both engine color masks in that region. The
changed cells are outside display, source scanning, and initializer self-feed
reads, while `XLAT` still observes the exact king score.

### 4. Keep the vector page in `BH` — minus one byte

With the captured-byte clone gone, `BH=01h` from `MOV BX,eval_db` can remain
the common code/data page. The six vector low-byte pointers move into the
unreachable island immediately after `RET`:

```text
piece type       2    3    4    5    6    7
low pointer     e4   ea   e9   ed   ef   ed
full pointer  01e4 01ea 01e9 01ed 01ef 01ed
```

That permits a three-byte disp8 `LEA`:

```asm
and  bl, 07h
lea  si, [byte bx + 53h]    ; 8D 77 53
lodsb
mov  ah, bh
xchg ax, si
```

The previous form required a four-byte disp16 `LEA`. The final image has 222
instruction bytes in file ranges `[0000h,0055h)` and `[005Bh,00E4h)`. The six
bytes `[0055h,005Bh)` are metadata protected from control-flow fallthrough by
the preceding `RET`.

## Earlier reductions from LeanChess

The 276-byte release had already combined several sizecoding techniques:

- stream the self-drawing board through DOS `INT 29h`, removing a render
  buffer and string printer;
- omit the unnecessary BIOS video-mode call while explicitly establishing
  `DF` and the row count;
- fold ASCII coordinate biases into one wrapping 16-bit base address;
- keep recursive depth live in `CX` instead of reloading it from the stack;
- fold pawn direction into the side-to-move color bit; and
- hold the piece type in `BX`, allowing Peter Ferrie's compact move-table
  addressing rewrite.

Git history and [`legacy/AttoChess-276.asm`](legacy/AttoChess-276.asm) preserve
that version in its original MASM/TASM form.

## Verification and proof scope

The release is accompanied by eight standalone SMT-LIB queries. Each was
replayed with Z3 4.16.0 and returned `UNSAT`:

1. `move_prologue_equivalence`
2. `pawn_predicate_equivalence`
3. `pawn_recursive_dead_inputs`
4. `pawn_undo_equivalence`
5. `pawn_contextual_equivalence`
6. `table_overlap_equivalence`
7. `pointer_metadata_equivalence`
8. `rejected_clone_deadness`

The proof directory contains the exact queries, native Z3 proof expressions,
solver statistics, and the canonical Unicorn differential report. Structural
audits additionally verify exact instruction boundaries, lossless
decode/re-encode, the metadata island, `BH=01h` dominance across nested
`PUSHA`/`POPA`, and rejected-path `AH`/`BH` deadness.

The independent Unicorn 2.1.4 harness compared complete modeled DOS event
traces and relocated board state for all 20 legal opening moves plus three
two-turn sequences. All 23 passed. The report SHA-256 is:

```text
ab632e7a55ed9ce43f26dae4803080e17c0b625b072a7fa23976f30b537b59f3
```

This evidence establishes the local and contextual contracts stated by the
queries for the exact fingerprinted artifact. It does **not** prove that 272
bytes is globally minimal among every possible x86 program, nor does it form a
mechanically composed unbounded whole-program bisimulation. In particular,
the contextual pawn query treats equal recursive score as an explicit
composition hypothesis. See [`proof/README.md`](proof/README.md) for the full
boundary and replay instructions.

## Rules and limitations

AttoChess follows the deliberately reduced rules of its sizecoding lineage:

- standard piece movement and captures with a real recursive material search;
- no castling, en passant, promotion, or full check/checkmate adjudication;
- trusted coordinate input rather than a complete move validator; and
- deliberate stopping when no move satisfies the engine's score condition.

These constraints matter when comparing byte counts. AttoChess is a playable
reduced chess engine, not a FIDE-complete engine.

## Lineage and credit

- **Dmitry Shechtman**, [LeanChess](https://github.com/leanchess/leanchess.github.io),
  the 288-byte program from which AttoChess is derived.
- **Óscar Toledo G.**, [Toledo Atomchess](https://github.com/nanochess/Toledo-Atomchess),
  the earlier DOS `.COM` record holder, 352 bytes in its usual form and 326 in
  the December 2019 HACK build.
- **Olivier Poudade**, [BootChess](http://olivier.poudade.free.fr/), the
  487-byte boot-sector ancestor.
- **David Horne**, 1K ZX Chess (1982), the 672-byte starting point.
- **Peter Ferrie**, the `BX`/`LEA` move-table rewrite in the 276-byte phase.

## License

MIT. AttoChess is Copyright © 2026 Nicholas Tanner. It is a derivative of
LeanChess, Copyright © 2019 Dmitry Shechtman. The complete inherited notice is
retained at the top of [`AttoChess.asm`](AttoChess.asm).
