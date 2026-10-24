; ============================================================================
;  AttoChess optimized candidate.
;
;  Copyright (c) 2026 Nicholas Tanner
;
;  This is a derivative work of Dmitry Shechtman's LeanChess. His copyright
;  and license are reproduced in full immediately below. Do not remove them.
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
;
; AttoChess 272-byte candidate, NASM syntax.
;
; Derived from the fingerprinted 276-byte AttoChess distribution artifact.
; It contains four compositionally checked one-byte reductions.
;
; (1) The move prologue exchanges zero into the source before testing the
;     resulting AL. On the nonempty path this is identical to the source;
;     on the empty path it changes no memory and enters the same deliberate
;     infinite loop. Reusing AL makes the three-byte memory CMP unnecessary.
;
; (2) The pawn predicate is occupancy == vector-parity. AND/NEG obtains the
;     occupancy bit in CF; RCL maps occupancy and vector parity into AL bits
;     0 and 1; TEST makes PF true iff those bits agree. PUSH/POP restores the
;     original AX while preserving PF. AH therefore remains available for
;     undo, eliminating the old destination clone in BH.
;
; (3) eval_db's final king value, 2Eh, is also init_db's first top-border fill
;     byte. It has the border bit for both 18h and 28h masks, is outside the
;     displayed/scanned board rows, and remains the exact XLAT value at index 7.
;     Overlapping the two tables removes one data byte.
;
; (4) AH-based undo leaves BH free. eval_db, moves_db, and all vectors reside
;     in runtime page 01xx, so BH=01h from MOV BX,eval_db can remain invariant.
;     MOVES_DB lives in the dead island after SUB_RET. Its absolute low-byte
;     vector pointers plus the preserved BH allow a disp8 LEA, saving one byte.

bits 16
cpu 186
org 100h

start:
    cld
    mov cx, 13
    mov si, init_db
    mov di, board_db

init_loop:
    push cx
    mov ax, 0A0Dh
    stosw
    stosw
    mov cl, 8
    lodsb
    test al, 80h
    jz init_cont
    dec si
    rep movsb

init_cont:
    rep stosb
    pop cx
    loop init_loop

main_loop:
    mov si, board_db + 24
    mov cl, 98

disp_loop:
    lodsb
    test al, 30h
    jz disp_cont

disp_piece:
    inc ax
    and al, 27h
    add al, 4Bh

disp_cont:
    int 29h
    loop disp_loop

play:
    mov dx, 1828h
    mov cl, 4
    push word main_loop
    mov ax, move_sub
    push ax
    push ax
    push word read_sub

read_sub:
    mov bp, di
    mov di, board_db + 123 + 0CE0h
    mov ah, 01h
    int 21h
    add di, ax
    int 21h
    imul ax, 12
    sub di, ax

sub_ret:
    ret

; Absolute low-byte vector pointers. SUB_RET prevents fallthrough, while all
; direct move calls enter MOVE_SUB below this table.
moves_db:
    moves_knight db vec_knight - $$
    moves_bishop db vec_bishop - $$
    moves_pawn   db vec_pawn   - $$
    moves_queen  db vec_king   - $$
    moves_rook   db vec_rook   - $$
    moves_king   db vec_king   - $$

; BX is 0100h+type, while MOVES_DB[type-2] is at
; 0100h+(MOVES_DB-$$)+(type-2).  Subtracting $$ makes this an absolute
; assembly-time scalar, so NASM can prove the displacement fits in int8.
moves_disp equ moves_db - $$ - 2

move_sub:
    xor ax, ax
    xchg al, [bp]
    test al, al
    jz $
    xchg al, [di]
    xchg dl, dh

    and al, 07h
    mov bx, eval_db
    xlatb
    jcxz sub_ret

next:
    pusha
    mov bp, board_db + 28

src_loop:
    mov bl, [bp]
    test bl, dl
    jnz src_cont

    ; Preserve BH=01h while isolating the type. MOVES_DISP=53h is the signed
    ; disp8 from BX=0100h+type to MOVES_DB[type-2].
    and bl, 07h
    jz src_cont

    ; The BYTE qualifier is an encoding proof obligation: NASM otherwise
    ; conservatively selects disp16 for a relocatable label expression.
    lea si, [byte bx + moves_disp]
    lodsb
    mov ah, bh
    xchg ax, si

vec_loop:
    lodsb

sign_loop:
    mov di, bp

dest_loop:
    cbw
    add di, ax
    mov ah, [di]
    test ah, dh
    jnz vec_cont

    cmp bl, 04h
    jne eval

pawn:
    push ax
    xor al, dh
    test al, 20h
    pop ax
    jz vec_cont

    ; Preserve AX while mapping occupancy and vector parity to two low bits.
    push ax
    and ah, dl
    neg ah
    rcl al, 1
    test al, 3
    pop ax
    jpo vec_cont

eval:
    pusha
    push bp
    push di

    mov si, sp
    dec cx
    call move_sub
    cmp al, [si + 35]
    pop di
    pop bp
    jl undo

best:
    mov [si + 35], al
    mov [si + 20], di
    mov [si + 24], bp

undo:
    popa
    ; The predicate restored AX, so AH still holds the original destination.
    xchg ah, [di]
    mov [bp], ah
    test [di], dl
    jnz vec_cont

    test bl, bl
    jpe dest_loop

vec_cont:
    neg al
    js sign_loop
    jnz vec_loop

src_cont:
    inc bp
    cmp bp, board_db + 120
    jnz src_loop

move_done:
    popa
    sub al, ah
    ret

    vec_knight db 10, 14, 23, 25, 0
    vec_pawn   db 12
    vec_bishop db 11, 13, 0
    vec_king   db 11, 13
    vec_rook   db 12, 1

eval_db:
    db 0, 0, 3, 3, 1, 9, 5

init_db:
    db 2Eh, 09h
    db 0A6h, 0A2h, 0A3h, 0A5h, 0A7h, 0A3h, 0A2h, 0A6h
    db 24h
    db 00h, 00h, 00h, 00h
    db 14h
    db 96h, 92h, 93h, 95h, 97h, 93h, 92h, 96h

board_db:
