; Cases: count, base, sel, which(0 down / 1 up) -> stores dirty, base lo, base hi, sel,
; then the arguments of the case's ShiftRows call (dst_y, src_y, batches, step), zeros without one
INCLUDE "scroll_syms.inc"           ; Down, Up: run.py, from the compiler's symbols
SECTION "code", ROM0[$1000]
ScrollCode: INCBIN "scroll_test_1000.bin"

SECTION "shift", ROM0[$0F00]
; ShiftRows stand-in (ezjr_scroll.c is linked with it here): records its four
; u8 arguments, sdcccall 0 at sp+2..5
ShiftRecorder:
    ld hl, sp+2
    ld de, wShift
    REPT 4
    ld a, [hl+]
    ld [de], a
    inc de
    ENDR
    ret

SECTION "hdr", ROM0[$100]
    nop
    jp Main
    ds $150 - @, 0
SECTION "main", ROM0[$150]
Main:
    di
    ld sp, $DFF0
    ld hl, Cases
    ld de, wOut
.next:
    ld a, [hl+]
    cp $FF
    jr z, .done
    ld [$C2A2], a            ; ENTRY_COUNT lo
    xor a
    ld [$C2A3], a
    ld a, [hl+]
    ld [wSt + 1], a          ; base lo
    xor a
    ld [wSt + 2], a
    ld [wSt], a              ; dirty
    ld a, [hl+]
    ld [wSt + 3], a          ; sel
    xor a
    ld [wShift], a
    ld [wShift + 1], a
    ld [wShift + 2], a
    ld [wShift + 3], a
    ld a, [hl+]
    push hl
    push de
    ld hl, wSt
    push hl                  ; st
    ld hl, 0
    push hl
    push hl
    push hl                  ; three pads
    and a
    jr nz, .up
    call Down
    jr .r
.up:
    call Up
.r:
    add sp, 8
    pop de
    ld hl, wSt
    REPT 8                   ; wSt, then wShift right after it
    ld a, [hl+]
    ld [de], a
    inc de
    ENDR
    pop hl
    jr .next
.done:
    ld a, $AA
    ld [wDone], a
.h: jr .h
Cases:
    ; count, base, sel, which
    db 39, 0, 0, 0           ; down from top: sel 1, dirty 2
    db 39, 0, 9, 0           ; down on row 9: base 1, rows moved, dirty 2
    db 39, 29, 9, 0          ; down on last (29+9=38): wrap to 0,0
    db 39, 0, 0, 1           ; up on first: base 29, sel 9
    db 39, 5, 0, 1           ; up on row 0 mid: base 4, rows moved, dirty 3
    db 39, 5, 3, 1           ; up mid page: sel 2, dirty 3
    db 4, 0, 3, 0            ; short list, down on last: wrap
    db 4, 0, 0, 1            ; short list, up on first: sel 3
    db $FF
SECTION "vars", WRAM0[$C000]
wOut: ds 64
wSt: ds 4
wShift: ds 4
wDone: ds 1
