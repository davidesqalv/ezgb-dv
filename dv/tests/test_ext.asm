; Test harness: runs Fit12Vis / Fit12Marq against a stub Fit12 that "fits" MAXFIT glyphs.
INCLUDE "ext_hide.asm"

DEF MAXFIT EQU 24

SECTION "stub", ROMX[$7100], BANK[2]
; Stub Fit12: records its len argument, returns E = min(string length within cap, MAXFIT)
StubFit12:
    ld hl, sp+8
    ld a, [hl]
    ld [wGotLen], a
    ld c, a
    and a
    jr nz, .c
    ld c, 40
.c:
    ld hl, sp+6
    ld a, [hl+]
    ld h, [hl]
    ld l, a
    ld e, 0
.l:
    ld a, e
    cp c
    jr nc, .d
    cp MAXFIT
    jr nc, .d
    ld a, [hl+]
    and a
    jr z, .d
    inc e
    jr .l
.d:
    ret

SECTION "hdr", ROM0[$100]
    nop
    jp Main
    ds $150 - @, 0

SECTION "main", ROM0[$150]
Main:
    di
    ld sp, $DFF0
    ld a, 2
    ld [$2000], a               ; MBC1: bank 2 at $4000
    ld de, wRes
    ld hl, wRes
    ld de, Cases
.next:
    ld a, [de]
    cp $FF
    jr z, .done
    ; case record: which, len, ptr lo, ptr hi
    ld [wWhich], a
    inc de
    ld a, [de]
    ld [wLen], a
    inc de
    ld a, [de]
    ld c, a
    inc de
    ld a, [de]
    ld b, a
    inc de
    push de
    push hl
    ld hl, $C800
    push hl                     ; xs
    ld a, [wLen]
    ld l, a
    ld h, 1                     ; col
    push hl
    push bc                     ; s
    ld hl, 0
    push hl
    push hl
    ld a, [wWhich]
    and a
    jr nz, .m
    call Fit12Vis
    jr .r
.m:
    call Fit12Marq
.r:
    add sp, 10
    pop hl
    ld a, [wGotLen]
    ld [hl+], a
    ld a, e
    ld [hl+], a
    pop de
    jr .next
.done:
    ld a, $AA
    ld [wDone], a
.halt:
    jr .halt

Cases:
    db 0, 0
    dw S1
    db 1, 0
    dw S1
    db 0, 0
    dw S2
    db 1, 0
    dw S2
    db 0, 0
    dw S3
    db 1, 0
    dw S3
    db 0, 0
    dw S4
    db 1, 0
    dw S4
    db 0, 0
    dw S5
    db 0, 0
    dw S6
    db 0, 0
    dw S7
    db 0, 5
    dw S8
    db 0, 0
    dw S9
    db 0, 0
    dw S10
    db 1, 0
    dw S10
    db $FF
S1:  db "Donkey Kong.gb", 0
S2:  db "Pokemon Puzzle Challenge.gbc", 0
S3:  db "Super Mario Land 2 - 6 Golden Coins.gb", 0
S4:  db "README.TXT", 0
S5:  db $C1, "Aladdin.gbc", 0
S6:  db ".gb", 0
S7:  db "Game.GBC", 0
S8:  db "Aladdin.gbc", 0
S9:  db "x.gbcx", 0
S10: db "Tetris.gbx", 0

SECTION "vars", WRAM0[$C000]
wRes:    ds 64
wGotLen: ds 1
wWhich:  ds 1
wLen:    ds 1
wDone:   ds 1
