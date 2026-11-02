; ezjr_scroll_down / ezjr_scroll_up (ezjr_scroll.c) case by case.
; A case is 9 bytes: count, base, sel, which (0 down / 1 up), the previous
; poll's pad report ($fff5), hFrame ($fffa), the repeat timer ($fff2), what
; the MoveHighlight stand-in answers (1 done, 0 declined), and the repeat
; count ($fff4).
; Each case leaves 16 bytes in wOut: dirty, base lo, base hi, sel, the
; RepaintRows call (called, k, up, 0), the MoveHighlight call (called, to),
; the marquee index at $cc31/$cc32 (set to $1234 before the case), the repeat
; timer and the repeat count after, and 2 spare.
INCLUDE "scroll_syms.inc"           ; Down, Up: run.py, from the compiler's symbols
SECTION "code", ROM0[$1000]
ScrollCode: INCBIN "scroll_test_1000.bin"

SECTION "repaint", ROM0[$0F00]
; RepaintRowsStub stand-in (ezjr_scroll.c is linked with it here):
; RepaintRows(st, k, up), sdcccall 0, st at sp+2, k at sp+4, up at sp+5.
; Records the call; the real one moves the window and leaves dirty 0, so the
; state shows what ezjr_scroll.c itself changed.
RepaintRecorder:
    ld a, 1
    ld [wRep], a
    ld hl, sp+4
    ld a, [hl+]
    ld [wRep + 1], a                ; k
    ld a, [hl]
    ld [wRep + 2], a                ; up
    ret

SECTION "move", ROM0[$0F40]
; MoveHighlightStub stand-in: MoveHighlight(st, to), sdcccall 0, st at sp+2,
; to at sp+4. Records the call; when wMoveRet is 1, does what MoveHighlight
; does to the state (sel = to, dirty 0) and returns 1 in E, else returns 0.
MoveRecorder:
    ld hl, sp+4
    ld a, [hl]
    ld [wMove + 1], a               ; to
    ld a, 1
    ld [wMove], a                   ; called
    ld a, [wMoveRet]
    and a
    jr z, .no
    ld hl, sp+2
    ld a, [hl+]
    ld h, [hl]
    ld l, a                         ; st
    xor a
    ld [hl+], a                     ; dirty
    inc hl
    inc hl
    ld a, [wMove + 1]
    ld [hl], a                      ; sel
    ld e, 1
    ret
.no:
    ld e, 0
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
    jp z, .done
    ld [$C2A2], a            ; ENTRY_COUNT lo
    xor a
    ld [$C2A3], a
    ld [wSt], a              ; dirty
    ld [wSt + 2], a          ; base hi
    ld [wRep], a
    ld [wRep + 1], a
    ld [wRep + 2], a
    ld [wRep + 3], a
    ld [wMove], a
    ld [wMove + 1], a
    ld a, [hl+]
    ld [wSt + 1], a          ; base lo
    ld a, [hl+]
    ld [wSt + 3], a          ; sel
    ld a, [hl+]
    ld b, a                  ; which
    ld a, [hl+]
    ldh [$FFF5], a           ; previous poll's report
    ld a, [hl+]
    ldh [$FFFA], a           ; hFrame
    ld a, [hl+]
    ldh [$FFF2], a           ; repeat timer
    ld a, [hl+]
    ld [wMoveRet], a
    ld a, [hl+]
    ldh [$FFF4], a           ; repeat count
    ld a, $34
    ld [$CC31], a
    ld a, $12
    ld [$CC32], a
    push hl
    push de
    ld hl, wSt
    push hl                  ; st
    ld hl, 0
    push hl
    push hl
    push hl                  ; three pads
    ld a, b
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
    REPT 10                  ; wSt (4), wRep (4), wMove (2)
    ld a, [hl+]
    ld [de], a
    inc de
    ENDR
    ld a, [$CC31]
    ld [de], a
    inc de
    ld a, [$CC32]
    ld [de], a
    inc de
    ldh a, [$FFF2]
    ld [de], a
    inc de
    ldh a, [$FFF4]
    ld [de], a
    inc de
    inc de
    inc de                   ; 16 per case
    pop hl
    jp .next
.done:
    ld a, $AA
    ld [wDone], a
.h: jr .h
Cases:
    ;  count base sel which prev  frame timer ret rep
    db 39,   0,   0,  0,    $00,  50,   0,    1,  7    ; down from the top: recolored to row 1 (a press: rep back to 0)
    db 39,   0,   0,  0,    $00,  50,   0,    0,  0    ; ...declined: the stock row-down repaint
    db 39,   0,   9,  0,    $00,  50,   0,    1,  0    ; down on row 9, a press: scroll by 1
    db 39,  29,   9,  0,    $00,  50,   0,    1,  0    ; down on the last (29+9=38): wrap to 0,0, all ten rows
    db 39,   0,   0,  1,    $00,  50,   0,    1,  0    ; up on the first: wrap to base 29, sel 9, all ten rows
    db 39,   5,   0,  1,    $00,  50,   0,    1,  0    ; up on row 0 mid, a press: scroll by 1
    db 39,   5,   3,  1,    $00,  50,   0,    1,  0    ; up mid page: recolored to row 2
    db 39,   5,   3,  1,    $00,  50,   0,    0,  0    ; ...declined: the stock row-up repaint
    db 4,    0,   3,  0,    $00,  50,   0,    1,  0    ; short list, down on the last: recolored to row 0
    db 4,    0,   3,  0,    $00,  50,   0,    0,  0    ; ...declined: the page repaint
    db 4,    0,   0,  1,    $00,  50,   0,    1,  0    ; short list, up on the first: recolored to row 3
    db 39,   0,   2,  0,    $08,  67,  50,    1,  0    ; DOWN held for 17 frames: no move yet
    db 39,   0,   2,  0,    $08,  68,  50,    1,  0    ; DOWN held for 18: repeats, next in 6 (timer 68 - 12)
    db 39,   0,   2,  1,    $04,  12, 250,    1,  0    ; UP held for 18 across hFrame's wrap: repeats
    db 39,   0,   2,  1,    $08,  60,  55,    1,  0    ; UP pressed while DOWN was down: a press, moves
    db 39,   0,   2,  0,    $08,  68,  50,    1,  1    ; 2nd repeat: still 6
    db 39,   0,   2,  0,    $08,  68,  50,    1,  2    ; 3rd: next in 5 (timer 68 - 13)
    db 39,   0,   2,  0,    $08,  68,  50,    1,  5    ; 6th: next in 4 (timer 68 - 14)
    db 39,   0,   2,  0,    $08,  68,  50,    1,  6    ; and on: next in 3 (timer 68 - 15), the count stays
    db 39,   0,   9,  0,    $08,  68,  50,    1,  2    ; held on row 9, 3rd repeat: scroll by 2
    db 39,   0,   9,  0,    $08,  68,  50,    1,  6    ; held on row 9, 7th repeat on: scroll by 4
    db 39,  27,   9,  0,    $08,  68,  50,    1,  6    ; ...with 2 entries below the window: by 2
    db 39,  28,   9,  0,    $08,  68,  50,    1,  6    ; ...with 1: by 1
    db 39,   5,   0,  1,    $04,  68,  50,    1,  4    ; held on row 0, 5th repeat: scroll up by 3
    db 39,   2,   0,  1,    $04,  68,  50,    1,  6    ; ...with 2 entries above the window: by 2
    db 39,   1,   0,  1,    $04,  68,  50,    1,  6    ; ...with 1: by 1
    db $FF
SECTION "vars", WRAM0[$C000]
wOut: ds 448
wSt: ds 4
wRep: ds 4
wMove: ds 2
wMoveRet: ds 1
wDone: ds 1
