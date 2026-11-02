INCLUDE "bank2_tabnum.asm"
SECTION "hdr", ROM0[$100]
    nop
    jp Main
    ds $150 - @, 0
SECTION "main", ROM0[$150]
Main:
    di
    ld sp, $DFF0
    ld a, 2
    ld [$2000], a
    ld hl, Cases
    ld de, wOut
.next:
    ld a, [hl+]
    cp $FF
    jr z, .done
    ld [ENTRY_COUNT], a
    ld a, [hl+]
    ld [ENTRY_COUNT + 1], a
    ld a, [hl+]
    ld c, a
    ld a, [hl+]
    ld b, a                     ; bc = string
    push hl
    push de
    ld h, d
    ld l, e                     ; hl = output slot
    ld d, b
    ld e, c
    call FormatCounter
    pop de
    ld hl, 8
    add hl, de
    ld d, h
    ld e, l
    pop hl
    jr .next
.done:
    ld a, $AA
    ld [wDone], a
.h: jr .h
Cases:
    dw 39
    dw S1
    dw 39
    dw S2
    dw 5
    dw S3
    dw 416
    dw S4
    dw 0
    dw S5
    dw 39
    dw S6
    dw 416
    dw S7
    db $FF
S1: db "2", 0
S2: db "  39"
S3: db "1", 0
S4: db " 100", 0
S5: db 0
S6: db "0039", 0                ; Digits4's form (MoveHighlight, CounterDigits)
S7: db "0416", 0
SECTION "vars", WRAM0[$C000]
wOut: ds 64
wDone: ds 1
