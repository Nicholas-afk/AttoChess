# AttoChess

**A complete, playable chess program for 16-bit x86 DOS — in 278 bytes.**

AttoChess is a size-optimized descendant of **LeanChess**. It plays the same game,
in the same environment, using the same 0x88-style board and recursive minimax
search — but assembles to **278 bytes**, ten bytes smaller than the 288-byte
program that previously held the record for the smallest working chess engine.

```
Engine              Bytes   Year   Author                Platform
----------------------------------------------------------------------
1K ZX Chess           672   1982   David Horne           Sinclair ZX81
BootChess             487   2015   Olivier Poudade       x86 boot sector
LeanChess             288   2019   Dmitry Shechtman      x86 DOS (.COM)
AttoChess             278   2026   Nicholas Tanner       x86 DOS (.COM)
```

> **What "working" means here.** AttoChess is not a byte-count stunt that only sets
> up a board. It boots, draws the position, reads your move from the keyboard,
> searches with real 4-ply recursion, replies with a legal move, and loops. The
> 278-byte figure is the assembled size of that whole program, verified
> byte-for-byte on the produced `.COM`.

---

## Lineage

This project stands on the work that came before it, and honoring that lineage is
part of the point.

- **[LeanChess](https://github.com/leanchess/leanchess.github.io)** — Dmitry
  Shechtman, 2019. The real breakthrough: it took the record from a 487-byte boot
  sector down to a 288-byte DOS `.COM`, with an elegant, genuinely readable design
  — a padded 0x88 board, a piece encoding that doubles as its own
  move-generation index, and a single recursive routine that both makes a move and
  finds the best reply. Every clever idea in AttoChess is one of these ideas taken
  a step further, and AttoChess is a **derivative work** that retains Shechtman's
  copyright and MIT license in full. If you find this interesting, read his source
  first.
- **[BootChess](http://olivier.poudade.free.fr/)** — Olivier Poudade, 2015. Fit a
  chess game into a 512-byte boot sector (487 bytes of code) and reset public
  expectations of how small chess could go.
- **1K ZX Chess** — David Horne, 1982. Squeezed a playable game into 672 bytes on a
  Sinclair ZX81 and stood as the benchmark for over thirty years.

---

## Verifying the size

The record claim is only worth anything if you can reproduce it. Assemble the
source and measure the output:

```bash
tasm AttoChess
tlink /t AttoChess        # /t produces a .COM, not an .EXE
ls -l AttoChess.com       # 278 bytes
```

There is nothing else in the image — no data-section padding, no separate render
buffer, no reserved board array baked into the file. Every byte in `AttoChess.com`
is code or table data the program actually uses.

---

## What makes AttoChess tiny

AttoChess keeps the original's core search verbatim. All ten bytes come from
rethinking the two things *around* the search — **how the board is drawn** and
**how your move is decoded** — plus one change inside the search loop that frees a
register. Here is every optimization, top to bottom.

### 1. The board draws itself — no render buffer, no `int 21h/09h`

This is the big one, and it removes the most bytes.

The original renders the position into a separate buffer: it walks the board,
transforms each square into a printable character, stores it, appends a `$`
terminator, and prints the whole string with DOS function `09h` (`int 21h`). That
path costs a buffer pointer setup, the copy loop's store, the terminator write,
and — because the buffer lives after the board — a reserved board array in the
image.

AttoChess deletes all of it. The board's border columns are laid out as
`CR, LF, CR, LF` (`0Dh, 0Ah, 0Dh, 0Ah`) instead of the previous `08h` filler. Both
CR and LF still have bit 3 set, so every existing border/color mask test fires
exactly as before — but now the raw board bytes are *already* a printable frame.
The display loop streams each byte straight to the console with **`int 29h`** (DOS
fast console output): borders become newlines, empty squares become NULs, and only
real pieces take the ASCII transform.

```asm
main_loop:
    mov si, offset board_db + 24   ; row 2 (black back rank), col 0
    mov cl, 98                     ; 8 rank rows + final CR,LF (CH=0)
disp_loop:
    lodsb                          ; read square contents
    test al, 30h                   ; piece?
    jz disp_cont                   ;   no -> emit raw (CR / LF / NUL)
    inc ax                         ; zero-align king
    and al, 27h                    ; isolate piece type + black/lowercase bit
    add al, 4Bh                    ; -> K, N, B, P, Q, R (upper/lower by color)
disp_cont:
    int 29h                        ; fast console output of AL
    loop disp_loop
```

Gone in one move: the render buffer, its pointer setup, the `$` terminator, the
`int 21h`/`09h` string print, **and** the reserved board array in the file image.

### 2. No BIOS mode-set — deterministic startup instead

The original opens with `int 10h` to force BIOS display mode 0. AttoChess drops it
and instead makes its two genuine entry assumptions explicit, which is both smaller
overall and correct regardless of how the program is launched:

```asm
start:
    cld                            ; DF is not guaranteed clear at entry
    mov cx, 13                     ; row count (entry CX is not guaranteed)
```

Streaming through `int 29h` needs no particular video mode, so the mode-set simply
isn't required.

### 3. The input decoder folds every constant into one base address

Reading a move means turning two typed characters (a file and a rank) into a board
address. The original does this in stages: read the file char, add it, read the
rank char, mask it down with `and al, 0Fh`, load `12` into `ah`, `mul` to get the
row offset, and subtract.

AttoChess collapses the arithmetic by pre-folding the ASCII bias constants directly
into the base address and letting 16-bit pointer math wrap around mod 64K. The
normalization step and the separate multiply setup both disappear:

```asm
read_sub:
    mov bp, di
    mov di, offset board_db + 123 + 0CE0h  ; base pre-folds the ASCII offsets
    mov ah, 01h
    int 21h                                ; read file char
    add di, ax                             ; AX = 0100h + file char
    int 21h                                ; read rank char
    imul ax, 12                            ; AX = 12 * (0130h + rank digit)
    sub di, ax                             ; land on the target square
```

`imul ax, 12` (an 80186 immediate-form multiply) replaces the `mov ah,12` + `mul
ah` pair, and the wrap-around base makes the explicit `and al, 0Fh` input mask
unnecessary.

### 4. The source loop frees CX so depth never has to be reloaded

Inside the recursive search, the original scans candidate source squares with a
counted `loop` (`mov cl, 92` … `loop src_loop`). That reuses CX as the loop
counter — which clobbers the search depth living in CX — so on every recursive call
it must **re-read the depth back off the stack frame** (`mov cx, [si + 32]`) before
decrementing it.

AttoChess walks the source squares by comparing the pointer to the end of the board
instead:

```asm
src_cont:
    inc bp
    cmp bp, offset board_db + 120  ; past the last square?
    jnz src_loop
```

CX is never touched, so it stays as the live depth counter for the whole scan. The
recursive call site then just does `dec cx` directly — the stack reload of depth is
gone entirely.

### 5. Pawn direction folded into the color bit

The original's pawn logic isolates the vector's sign bit, shifts it into alignment
with the color bit, XORs against the side-to-move, and branches on parity — several
instructions of bit-shuffling. AttoChess folds the forward/backward test straight
into color bit 5 with a single `xor al, dh`, and reuses vector parity (odd offset =
diagonal) to tell captures from pushes:

```asm
pawn:
    push ax
    xor al, dh          ; bit 5 := vector sign XOR side to move
    test al, 20h        ; forward for the moving color?
    pop ax              ; POP leaves flags intact
    jz vec_cont         ;   backward -> reject
    test al, 1          ; odd offset (+/-11, +/-13) = diagonal?
    jnz pawn_cont       ;   diagonal -> must capture
    xor ah, 30h         ; straight (+/-12): invert dest color for the empty test
pawn_cont:
    test ah, dl
    jz vec_cont
```

Because the direction test now keys off the side-to-move color rather than an
absolute sign, pawns move correctly for **both** colors from the one code path.

---

## Building & running

AttoChess is written in MASM/TASM syntax targeting the 80186.

### Assemble with TASM (Turbo Assembler)

```bash
tasm AttoChess
tlink /t AttoChess        # /t produces a .COM, not an .EXE
```

This yields `AttoChess.com` — a 278-byte DOS executable.

### Run under DOSBox

```bash
dosbox
```

Then, at the DOSBox prompt:

```
mount c: .
c:
AttoChess.com
```

Any real or emulated 16-bit DOS environment (DOSBox, PCem, 86Box, or genuine
hardware) works — the program uses only standard DOS `int 21h`/`int 29h` calls.

### How to play

You are **White**; the computer plays **Black** and answers automatically. Enter a
move as four characters — the source file+rank followed by the destination
file+rank — for example:

```
e2e4
```

The board redraws after each pair of moves. AttoChess searches four plies deep.

---

## Scope and limitations

AttoChess inherits its rule set from the program it was golfed from, and being
honest about it is part of the point:

- It plays standard piece movement and captures with a real recursive search.
- Like its ancestors in this size class, it does **not** implement castling, en
  passant, pawn promotion, or full check/checkmate adjudication; a side with no
  legal move that scores at or above zero simply halts.
- Input is trusted — it expects well-formed coordinates and does not validate
  against illegal moves the way a full engine would.

These are the classic trade-offs of sub-1K chess, and they are exactly the
constraints under which the byte count is a meaningful record.

---

## License

MIT License — see [LICENSE](LICENSE).

- **Copyright © 2026 Nicholas Tanner** (AttoChess)
- **Copyright © 2019 Dmitry Shechtman** (LeanChess)

AttoChess is a derivative work and retains Dmitry Shechtman's original copyright
notice and MIT license in full at the top of `AttoChess.asm`, as the license
requires. Please keep it there.

## Credits

- **Dmitry Shechtman** — [LeanChess](https://github.com/leanchess/leanchess.github.io),
  the 288-byte program this is built on. The foundation for everything here.
- **Olivier Poudade** — [BootChess](http://olivier.poudade.free.fr/), the 487-byte
  boot-sector ancestor.
- **David Horne** — 1K ZX Chess (1982), the 672-byte original that started the
  chase.
