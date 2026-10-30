DEF META_PAGE EQU 1
DEF REC_PAGE0 EQU 2
DEF KEY_PAGE EQU 15
INCLUDE "bank5.asm"
SECTION "hdr", ROM0[$100]
    nop
    jp Main
    ds $150 - @, 0
SECTION "main", ROM0[$150]
Main:
    di
    ld sp, $DFF0
    ld a, $0A
    ld [$0000], a
    ld a, META_PAGE                 ; fill the meta page with garbage: every byte $FF
    ld [$4000], a
    ld hl, $B000
    ld bc, $0200
.g: ld a, $FF
    ld [hl+], a
    dec bc
    ld a, b
    or c
    jr nz, .g
    ld a, 5
    ld [$2000], a
    ld hl, Path
    ld de, $C2A6
.c: ld a, [hl+]
    ld [de], a
    inc de
    and a
    jr nz, .c
    call PlayCount
    call PlayCount
    ld a, META_PAGE
    ld [$4000], a
    ld hl, $B000
    ld de, wOut
    ld bc, 264
.o: ld a, [hl+]
    ld [de], a
    inc de
    dec bc
    ld a, b
    or c
    jr nz, .o
    ld a, $AA
    ld [wDone], a
.h: jr .h
Path: db "/Pokemon Crystal.gbc", 0
SECTION "vars", WRAM0[$C000]
wOut: ds 264
wDone: ds 1
