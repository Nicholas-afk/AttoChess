# AttoChess — The world's smallest chess engine

**The world's smallest chess engine, in just 272 bytes.**

Created by **Nicholas Tanner**, AttoChess is a playable 16-bit x86 DOS chess
engine with board display, coordinate input, and a real four-ply recursive
search. The entire executable—including code and tables—is **272 bytes**.

AttoChess is a size-optimized descendant of Dmitry Shechtman's
[LeanChess](https://github.com/leanchess/leanchess.github.io). It initializes
and draws its own board, reads a move, searches four plies recursively, chooses
a reply, updates the position, and repeats. It uses deliberately reduced chess
rules; see the [rules and limitations](#rules-and-limitations).

[Play it in the browser](https://nicholas-afk.github.io/AttoChess/) ·
[Download the COM](ATTOCHES.COM) · [Read the source](AttoChess.asm) ·
[Inspect the proof evidence](proof/README.md)

## Smallest chess program: historical comparison

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
326 bytes.

## AttoChess questions and answers

### What is the world's smallest chess engine?

AttoChess is the world's smallest chess engine: a 272-byte x86 DOS program by
Nicholas Tanner. It displays its own board, accepts coordinate moves, and
calculates replies with a four-ply recursive search. Like the other programs in
its sizecoding lineage, it implements a reduced set of chess rules.

### What does the 272-byte size include?

All instructions and tables in the `ATTOCHES.COM` executable. The count is the
executable's file size, not its runtime memory usage. DOS, the browser interface,
and the emulator used for online play are outside that count. The
[build commands and SHA-256 hashes](#reproduce-the-272-byte-image) let you
reproduce and identify the exact program.

### Can I play AttoChess online?

Yes. [Play AttoChess in your browser](https://nicholas-afk.github.io/AttoChess/#machine)
or download the executable and [run it under DOSBox](#run-it). You play White;
AttoChess plays Black. Enter moves such as `e2e4`.

### Why do older articles mention 278 or 276 bytes?

Those figures describe earlier AttoChess versions. The current executable is
272 bytes. The [legacy directory](legacy/README.md) preserves earlier builds
and their history; the instructions below identify the current build.

### Does AttoChess implement every chess rule?

No. AttoChess omits castling, en passant, pawn promotion, full check/checkmate
adjudication, and complete move validation. Read the
[rules and limitations](#rules-and-limitations) before playing or comparing
program sizes. The [verification evidence](#verification-and-proof-scope)
describes its exact proof boundaries.

## Reproduce the 272-byte image

The current source uses NASM syntax and targets the Intel 80186 instruction
set. NASM 3.02 was used for the release build.

```sh
nasm -f bin -w+error -o ATTOCHES.COM AttoChess.asm
wc -c ATTOCHES.COM
shasum -a 256 AttoChess.asm ATTOCHES.COM
```

Expected output:

```text
272 ATTOCHES.COM
f35cd48d7621ff73ec1013d17e9b216bf5564e47efd43691cc6a35dd1c15e5bc  AttoChess.asm
1e395c1e523f900674add7e86639f248c4658678f08c85b0d6bb2652f5657003  ATTOCHES.COM
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

The computer calculates Black's reply and redraws the board. Search starts
with a best score of -128, so it keeps playing when every reply loses material.
The two-byte initializer is offset by removing a redundant pawn occupancy
mask; the executable remains 272 bytes.

## Size reductions

The original 272-byte build combined four one-byte reductions to the 276-byte
program. The fourth depends on the second freeing `BH`. The current build
reuses two pawn-predicate bytes for the losing-reply initializer.

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
neg  ah
rcl  al, 1
test al, 3
pop  ax
jpo  vec_cont
```

`POP` restores `AX` without changing flags. This leaves the captured byte in
`AH`, so undo can use `XCHG AH,[DI]` and the old two-byte `MOV BH,AH` clone
disappears. The earlier destination guard already rejects friendly pieces and
borders, so any remaining nonzero cell is an enemy piece. `NEG` alone sets the
occupancy carry; the original `AND AH,DL` is unnecessary.

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

The current build includes a replayable Z3 query for the shortened pawn
predicate and the -128 selection floor, plus a Unicorn regression report.
The query returns `UNSAT` under Z3 4.16.0. All 23 opening/two-turn sequences
match a straightforward 274-byte control with the same selection fix, and
100 synthetic positions at depth 3 match in scores and selected moves.

A regression fixture reproduces the old stop after `b5a5` in
`7k/p7/8/1Q6/8/8/8/7K w - - 0 1`; the current build plays `a7a6` and
returns to input. The full game-flow tests retain the normal four-ply search.

The previous build's eight queries and differential report remain available
as historical evidence. They do not certify the changed search behavior.
See [`proof/README.md`](proof/README.md) for exact fingerprints, replay commands,
assumptions, and the boundary of both sets of evidence. Neither set proves
whole-program correctness or global byte minimality.

## Rules and limitations

AttoChess follows the deliberately reduced rules of its sizecoding lineage:

- standard piece movement and captures with a real recursive material search;
- no castling, en passant, promotion, or full check/checkmate adjudication;
- trusted coordinate input rather than a complete move validator; and
- deliberate stopping when no move is generated.

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
