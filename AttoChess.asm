; ============================================================================
;  AttoChess -- a complete chess program for 16-bit x86 DOS in 276 bytes.
;
;  Copyright (c) 2026 Nicholas Tanner
;
;  AttoChess renders the board by streaming it straight to the console with
;  INT 29h, folds the input decoder's ASCII constants into a single wrapping
;  base address, and keeps the recursive search's depth counter live in CX.
;
;  This is a derivative work. It builds on -- and gratefully retains the
;  license and attribution of -- Dmitry Shechtman's original, reproduced in
;  full immediately below. Do not remove his notice.
; ============================================================================
;
; Copyright (c) 2019 Dmitry Shechtman
;
; Permission is hereby granted, free of charge, to any person obtaining a copy
; of this software and associated documentation files (the "Software"), to deal
; in the Software without restriction, including without limitation the rights
; to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
; copies of the Software, and to permit persons to whom the Software is
; furnished to do so, subject to the following conditions:
;
; The above copyright notice and this permission notice shall be included in all
; copies or substantial portions of the Software.
;
; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
; IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
; FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
; AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
; LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
; OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
; SOFTWARE.

; The 12-byte board rows carry CR,LF,CR,LF (0Dh,0Ah,0Dh,0Ah) in their first four
; columns instead of the original 08h border filler.  Every CR/LF byte still has
; bit 3 set, so all border/color mask tests fire exactly as before, yet the raw
; board doubles as its own printable frame: the display loop streams board bytes
; straight to the console with INT 29h (borders become newlines, empties become
; NULs, pieces get the +1 / AND 27h / ADD 4Bh ASCII transform).  This removes the
; separate render buffer, the '$'-terminated INT 21h/09h write, the INT 10h mode
; set, and the trailing board reservation from the image.

.model tiny
.186
code segment
    org 100h
    assume cs: code

start:
    cld                                        ;DF is not guaranteed clear at entry
    mov cx, 13                                 ;Row count (entry CX is not guaranteed);
                                               ;row 12 borders knight jumps from h1
    mov si, offset init_db                     ;Set row metadata address
    mov di, offset board_db                    ;Set board address

init_loop:
    push cx                                    ;Save row counter
    mov ax, 0A0Dh                              ;Border = CR,LF
    stosw                                      ;Write two bytes
    stosw                                      ;Cols 0-3: 0D 0A 0D 0A
    mov cl, 8                                  ;Set square counter
    lodsb                                      ;Read one byte
    test al, 80h                               ;First rank?
    jz init_cont                               ;No, proceed to write row
    dec si                                     ;Marker doubles as first piece
    rep movsb                                  ;Copy row

init_cont:
    rep stosb                                  ;Write row
    pop cx                                     ;Restore row counter
    loop init_loop                             ;Rows 10+ self-feed from board

main_loop:
    mov si, offset board_db + 24               ;Row 2 (black back rank), col 0
    mov cl, 98                                 ;8 rank rows + final CR,LF (CH=0)

disp_loop:
    lodsb                                      ;Read square contents
    test al, 30h                               ;Piece?
    jz disp_cont                               ;No, emit raw (CR/LF/NUL)

disp_piece:
    inc ax                                     ;Zero-align king
    and al, 27h                                ;Isolate piece type and black/lowercase
    add al, 4Bh                                ;King, (none), (reserved), kNight, bishOp, Pawn, Queen, Rook

disp_cont:
    int 29h                                    ;DOS fast console output (AL)
    loop disp_loop                             ;Move to next square

play:
    mov dx, 1828h                              ;Set player's and opponent's colors
    mov cl, 4                                  ;Set search depth
    push offset main_loop                      ;Repeat forever
    mov ax, offset move_sub                    ;Perform two moves:
    push ax                                    ;Perform computer's move
    push ax                                    ;Perform human's move
    push offset read_sub                       ;Read destination square

;Read square from input
;Output:
;  DI - Square address
read_sub:
    mov bp, di                                 ;Clone address
    mov di, offset board_db + 123 + 0CE0h      ;Base folds in ASCII offsets (mod 64K)
    mov ah, 01h                                ;Read character
    int 21h                                    ;DOS I/O function
    add di, ax                                 ;AX = 0100h + file char
    int 21h                                    ;DOS I/O function
    imul ax, 12                                ;AX = 12 * (0130h + rank digit)
    sub di, ax                                 ;Subtract result from base address

sub_ret:
    ret

;Perform move and find best next move
;Input:
;  DL - Player's color + border
;  DH - Opponent's color + border
;  CX - Search depth
;  BP - Source square address
;  DI - Destination square address
;Output:
;  AL - Player's max value
;  AH - Opponent's max value
;  DL - Opponent's color + border
;  DH - Player's color + border
;  SI - Opponent's best source square address
;  DI - Opponent's best destination square address
move_sub:
    cmp [bp], ch                               ;CH=0: empty source = search wrote no best
    jz $                                       ;No move scores >= 0: halt (mate/loss)
    xor ax, ax                                 ;Clear contents + opponent's max value
    xchg al, [bp]                              ;Read and write source square
    xchg al, [di]                              ;Read and write destination square
    xchg dl, dh                                ;Swap player's and opponent's colors

    and al, 07h                                ;Isolate piece type
    mov bx, offset eval_db                     ;Set base values' address
    xlat                                       ;Get player's gain
    jcxz sub_ret                               ;If depth is zero, return

next:
    pusha                                      ;Save all GP registers
    mov bp, offset board_db + 28               ;Start from top left corner

src_loop:
    mov bl, [bp]                               ;Read source square
    test bl, dl                                ;Opponent's piece or border?
    jnz src_cont                               ;Yes, proceed to next source square

    and bx, 07h                                ;Isolate piece type
    jz src_cont                                ;No piece, proceed to next source square

    lea si, [bx + offset moves_knight - 2]     ;Calculate absolute metadata address
    lodsb                                      ;Read relative vectors address
    cbw                                        ;Zero AH
    add si, ax                                 ;Calculate absolute vectors address

vec_loop:
    lodsb                                      ;Read vector

sign_loop:
    mov di, bp                                 ;Clone source square address

dest_loop:
    cbw                                        ;Extend vector's sign
    add di, ax                                 ;Calculate destination square address
    mov ah, [di]                               ;Read destination square
    mov bh, ah                                 ;Clone destination square contents
    test ah, dh                                ;Player's piece or border?
    jnz vec_cont                               ;Yes, proceed to next vector

    cmp bl, 04h                                ;Black or white pawn?
    jne eval                                   ;No, proceed to evaluate move

pawn:
    push ax                                    ;Save vector (AL) + destination (AH)
    xor al, dh                                 ;Bit 5 := vector sign XOR side to move
    test al, 20h                               ;Forward for the moving color?
    pop ax                                     ;Restore; POP leaves flags intact
    jz vec_cont                                ;Backward move, proceed to next vector
    test al, 1                                 ;Odd offset (+/-11, +/-13) = diagonal
    jnz pawn_cont                              ;Diagonal, must capture

pawn_inv:
    xor ah, 30h                                ;Straight (+/-12): invert dest's color

pawn_cont:
    test ah, dl                                ;Opponent's piece (or border)?
    jz vec_cont                                ;No, proceed to next vector

eval:
    pusha                                      ;Save all GP registers
    push bp                                    ;Save source square address
    push di                                    ;Save destination square address

    mov si, sp                                 ;Clone stack pointer
    dec cx                                     ;Decrement depth (restored by popa)
    call move_sub                              ;Recursively call self
    cmp al, [si + 35]                          ;Max value exceeds current value?
    pop di                                     ;Restore destination square address
    pop bp                                     ;Restore source square address
    jl undo                                    ;Yes, proceed to undo move

best:
    mov [si + 35], al                          ;Write max value
    mov [si + 20], di                          ;Write destination square address
    mov [si + 24], bp                          ;Write source square address

undo:
    popa                                       ;Restore all GP registers
    xchg bh, [di]                              ;Read and write original destination square
    mov [bp], bh                               ;Write original source square
    test [di], dl                              ;Opponent's piece (or border)?
    jnz vec_cont                               ;Yes, proceed to next vector

    test bl, bl                                ;Check piece type
    jp dest_loop                               ;Slider, move to next destination

vec_cont:
    neg al                                     ;Invert vector
    js sign_loop                               ;Negative, proceed to reset destination address
    jnz vec_loop                               ;Non-zero, move to next vector

src_cont:
    inc bp                                     ;Increment source square address
    cmp bp, offset board_db + 120              ;Past last square?
    jnz src_loop                               ;No, move to next source

move_done:
    popa                                       ;Restore all GP registers
    sub al, ah                                 ;Calculate player's max value
    ret

moves_db:
    moves_knight db vec_knight - moves_knight - 1
    moves_bishop db vec_bishop - moves_bishop - 1
    moves_pawn   db vec_pawn   - moves_pawn   - 1
    moves_queen  db vec_king   - moves_queen  - 1
    moves_rook   db vec_rook   - moves_rook   - 1
    moves_king   db vec_king   - moves_king   - 1

    vec_knight   db  10,  14,  23,  25,   0
    vec_pawn     db  12
    vec_bishop   db  11,  13,   0
    vec_king     db  11,  13
    vec_rook     db  12,   1

eval_db: ;[0] doubles as vector terminator
    db 0, 0, 3, 3, 1, 9, 5, 46

init_db:
    db 09h, 09h                                ;2 border rows (fill 09h)
    db 0A6h, 0A2h, 0A3h, 0A5h, 0A7h, 0A3h, 0A2h, 0A6h
    db 24h
    db 00h, 00h, 00h, 00h
    db 14h
    db 96h, 92h, 93h, 95h, 97h, 93h, 92h, 96h

board_db: ;Rows 10+ self-feed; occupies RAM only, not the image

code ends
end start
