# AttoChess

A complete, playable chess program for 16-bit x86 DOS, in 276 bytes.

AttoChess is a size-optimized descendant of LeanChess. Same game, same
environment, same 0x88-style board and recursive minimax search, but it
assembles to 276 bytes. That is twelve bytes under the 288-byte program that
previously held the record for the smallest working chess engine.

```
Engine              Bytes   Year   Author                Platform
----------------------------------------------------------------------
1K ZX Chess           672   1982   David Horne           Sinclair ZX81
BootChess             487   2015   Olivier Poudade       x86 boot sector
Toledo Atomchess      352   2015   Óscar Toledo G.       x86 DOS (.COM)
LeanChess             288   2019   Dmitry Shechtman      x86 DOS (.COM)
AttoChess             276   2026   Nicholas Tanner       x86 DOS (.COM)
```

> **What "working" means here.** AttoChess is not a byte-count stunt that only
> sets up a board. It boots, draws the position, reads your move from the
> keyboard, searches four plies of real recursion, replies with a legal move,
> and loops. The 276 bytes are the assembled size of all of that, measured on
> the produced `.COM`.

---

## Lineage

Almost nothing here is a new idea. It is mostly other people's ideas pushed one
step further, so the chain is worth spelling out.

- **[LeanChess](https://github.com/leanchess/leanchess.github.io)**, Dmitry
  Shechtman, 2019. This is the one that mattered. It took the record from a
  487-byte boot sector down to a 288-byte DOS `.COM`, and did it with a design
  that is genuinely readable: a padded 0x88 board, a piece encoding that doubles
  as its own move-generation index, and one recursive routine that both makes a
  move and finds the best reply. AttoChess is a derivative work and keeps
  Shechtman's copyright and MIT license intact. If any of this interests you,
  read his source before mine.
- **[Toledo Atomchess](https://github.com/nanochess/Toledo-Atomchess)**, Óscar
  Toledo G. (nanochess), 2015. Held the DOS `.COM` record between BootChess and
  LeanChess, and got refined over several years down to 352 bytes (356 as a
  bootable sector, 326 in its stripped "HACK" build). Like everything at this
  size, AttoChess included, it leaves out castling, en passant, and promotion.
  Write-ups of this record tend to jump straight from 487 to 288 and skip it.
- **[BootChess](http://olivier.poudade.free.fr/)**, Olivier Poudade, 2015. Fit a
  chess game into a 512-byte boot sector, 487 bytes of it code. This is roughly
  where the modern version of the contest starts.
- **1K ZX Chess**, David Horne, 1982. Squeezed a playable game into 672 bytes on
  a Sinclair ZX81, and it held for over thirty years.

---

## Verifying the size

A size record you cannot reproduce is not worth much. Assemble the source and
measure the output yourself:

```bash
tasm AttoChess
tlink /t AttoChess        # /t produces a .COM, not an .EXE
ls -l AttoChess.com       # 276 bytes
```

Nothing else is in that image. There is no data-section padding, no separate
render buffer, and no board array reserved in the file. Every byte of
`AttoChess.com` is code or table data the program actually uses.

---

## What makes AttoChess tiny

The core search is unchanged from LeanChess. All twelve bytes come out of the
two things around it, how the board is drawn and how your move is decoded, plus
two changes inside the search loop: one frees a register, the other tightens the
move-table addressing. Every optimization, in order.

### 1. The board draws itself

This one saves the most. The original renders the position into a separate
buffer: it walks the board, transforms each square into a printable character,
stores it, appends a `$` terminator, and prints the whole string with DOS
function `09h` (`int 21h`). That path costs a buffer pointer setup, the copy
loop's store, the terminator write, and, because the buffer lives after the
board, a reserved board array in the image.

AttoChess drops all of it. The board's border columns are laid out as
`CR, LF, CR, LF` (`0Dh, 0Ah, 0Dh, 0Ah`) rather than the `08h` filler LeanChess
used. CR and LF both have bit 3 set, so every existing border/color mask test
fires exactly as before, except now the raw board bytes are already a printable
frame. The display loop streams each byte straight to the console with `int 29h`
(DOS fast console output): borders become newlines, empty squares become NULs,
and only real pieces take the ASCII transform.

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

That takes out the render buffer, its pointer setup, the `$` terminator, the
`int 21h`/`09h` string print, and the reserved board array in the file image.

### 2. No BIOS mode-set

The original opens with `int 10h` to force BIOS display mode 0. AttoChess drops
it and makes its two genuine entry assumptions explicit instead, which is both
smaller overall and correct regardless of how the program is launched:

```asm
start:
    cld                            ; DF is not guaranteed clear at entry
    mov cx, 13                     ; row count (entry CX is not guaranteed)
```

Streaming through `int 29h` works in whatever video mode you happen to be in, so
the mode-set is not needed.

### 3. The input decoder folds every constant into one base address

Reading a move means turning two typed characters (a file and a rank) into a
board address. The original does this in stages: read the file char, add it,
read the rank char, mask it down with `and al, 0Fh`, load `12` into `ah`, `mul`
to get the row offset, and subtract.

AttoChess collapses the arithmetic by pre-folding the ASCII bias constants into
the base address and letting 16-bit pointer math wrap around mod 64K. The
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

### 4. The source loop leaves CX alone, so depth is never reloaded

Inside the recursive search, the original scans candidate source squares with a
counted `loop` (`mov cl, 92` … `loop src_loop`). That reuses CX as the loop
counter, which clobbers the search depth living there, so every recursive call
has to re-read the depth back off the stack frame (`mov cx, [si + 32]`) before
decrementing it.

AttoChess walks the source squares by comparing the pointer against the end of
the board instead:

```asm
src_cont:
    inc bp
    cmp bp, offset board_db + 120  ; past the last square?
    jnz src_loop
```

CX is never touched, so it stays the live depth counter for the whole scan. The
recursive call site then just does `dec cx`, and the stack reload of depth is
gone entirely.

### 5. Pawn direction folded into the color bit

The original's pawn logic isolates the vector's sign bit, shifts it into
alignment with the color bit, XORs against the side-to-move, and branches on
parity, which is several instructions of bit-shuffling. AttoChess folds the
forward/backward test straight into color bit 5 with a single `xor al, dh`, and
reuses vector parity (odd offset means diagonal) to tell captures from pushes:

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
absolute sign, pawns move correctly for both colors from the one code path.

### 6. Piece type held in BX, so the move-table address folds into one `lea`

*Contributed by [Peter Ferrie](https://github.com/peterferrie).*

The source loop reads a square, masks it down to a piece type, and uses that as
an index into the move-vector metadata. Holding that index in AX costs a
separate copy into BL and a two-instruction address calculation:

```asm
    mov al, [bp]
    and ax, 07h
    mov bl, al                          ; save piece type
    mov si, offset moves_knight - 2     ; base
    add si, ax                          ; + index
```

Reading straight into BL means the index is *already* where the slider test
later needs it, and the whole address computation collapses into a single `lea`:

```asm
    mov bl, [bp]
    and bx, 07h                         ; also zeroes BH
    lea si, [bx + offset moves_knight - 2]
    lodsb
    cbw                                 ; AH is no longer zeroed by the AND
```

There is one subtlety. The original `and ax, 07h` was doing double duty: it also
cleared AH, so the following `add si, ax` treated the loaded byte as a 16-bit
value. Masking BX leaves AH untouched, so a one-byte `cbw` has to restore that
invariant. Net saving: 2 bytes.

---

## Building & running

AttoChess is written in MASM/TASM syntax targeting the 80186.

### Assemble with TASM (Turbo Assembler)

```bash
tasm AttoChess
tlink /t AttoChess        # /t produces a .COM, not an .EXE
```

This yields `AttoChess.com`, a 276-byte DOS executable.

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

Any real or emulated 16-bit DOS environment works (DOSBox, PCem, 86Box, or
actual hardware), since the program uses only standard DOS `int 21h`/`int 29h`
calls.

### How to play

You play White. The computer plays Black and answers on its own. Enter a move as
four characters, source file and rank followed by destination file and rank:

```
e2e4
```

The board redraws after each pair of moves. AttoChess searches four plies deep.

---

## Scope and limitations

AttoChess inherits its rule set from the program it was golfed from. What that
means in practice:

- It plays standard piece movement and captures with a real recursive search.
- Like its ancestors at this size, it does not implement castling, en passant,
  pawn promotion, or full check/checkmate adjudication. A side with no legal
  move that scores at or above zero simply halts.
- Input is trusted. It expects well-formed coordinates and does not validate
  against illegal moves the way a full engine would.

Those are the standard trade-offs of sub-1K chess, and every program in the
table above makes them. The byte count is only a meaningful comparison because
they all play by the same reduced rules.

---

## License

MIT License. See [LICENSE](LICENSE).

- Copyright © 2026 Nicholas Tanner (AttoChess)
- Copyright © 2019 Dmitry Shechtman (LeanChess)

AttoChess is a derivative work and retains Dmitry Shechtman's original copyright
notice and MIT license in full at the top of `AttoChess.asm`, as the license
requires. Please keep it there.

## Credits

- **Dmitry Shechtman**, [LeanChess](https://github.com/leanchess/leanchess.github.io),
  the 288-byte program this is built on.
- **Óscar Toledo G.**, [Toledo Atomchess](https://github.com/nanochess/Toledo-Atomchess),
  which held the DOS `.COM` record between BootChess and LeanChess.
- **Olivier Poudade**, [BootChess](http://olivier.poudade.free.fr/), the
  487-byte boot-sector ancestor.
- **David Horne**, 1K ZX Chess (1982), the 672-byte original that started the
  chase.
- **[Peter Ferrie](https://github.com/peterferrie)**, the BX/`lea` rewrite of the
  move-table addressing in the source loop (§6), worth 2 bytes.
