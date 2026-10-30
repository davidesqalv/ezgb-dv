DEF META_PAGE EQU 1
DEF REC_PAGE0 EQU 2
DEF KEY_PAGE EQU 15
INCLUDE "bank5.asm"
SECTION "data", ROMX[$4000], BANK[6]
TTable: INCBIN "t_table.bin"
TRecs:  INCBIN "t_recs.bin"
TRecsEnd:
SECTION "hdr", ROM0[$100]
    nop
    jp Main
    ds $150 - @, 0
SECTION "main", ROM0[$150]
MACRO COPY6
    ld a, 6
    ld [$2000], a
    ld a, \3
    ld [$4000], a
    ld hl, \1
    ld de, \4
    ld bc, \2
.loop\@:
    ld a, [hl+]
    ld [de], a
    inc de
    dec bc
    ld a, b
    or c
    jr nz, .loop\@
ENDM
MACRO NAME                          ; copy string \1 to NAME_BUF
    ld hl, \1
    ld de, NAME_BUF
.n\@:
    ld a, [hl+]
    ld [de], a
    inc de
    and a
    jr nz, .n\@
ENDM
MACRO SAVE_E                           ; store e at wRes + \1
    ld a, e
    ld [wRes + \1], a
ENDM
Main:
    di
    ld sp, $DFF0
    ld a, $0A
    ld [$0000], a
    COPY6 TTable, 256, META_PAGE, $B000
    ld a, META_PAGE
    ld [$4000], a
    ld hl, $B104
    ld [hl], $45
    inc hl
    ld [hl], $5A
    inc hl
    ld [hl], $4A
    inc hl
    ld [hl], $52
    COPY6 TRecs, TRecsEnd - TRecs, REC_PAGE0, $A000
    ld a, 5
    ld [$2000], a
    NAME SAladdin
    call StarQuery
    SAVE_E 0                           ; 0: not starred
    call StarToggle
    SAVE_E 1                           ; 1: now starred
    call StarQuery
    SAVE_E 2                           ; 1
    call StarToggle
    SAVE_E 3                           ; 0
    NAME SNew
    call StarToggle
    SAVE_E 4                           ; 1: new entry, starred
    ld a, 6
    ld [ENTRY_COUNT], a
    xor a
    ld [ENTRY_COUNT + 1], a
    ld a, 3                         ; page 3 on, as after the sort
    call SetFpgaPage
    call MarkStars
    ld a, REC_PAGE0                 ; copy byte 252..254 of each record out
    ld [$4000], a
    ld hl, $A000 + 252
    ld de, wMarks
    ld b, 6
.m: ld a, [hl+]
    ld [de], a
    inc de
    ld a, [hl+]
    ld [de], a
    inc de
    ld a, [hl]
    ld [de], a
    inc de
    push bc
    ld bc, 255 - 2
    add hl, bc
    pop bc
    dec b
    jr nz, .m
    ld a, REC_PAGE0                 ; names intact?
    ld [$4000], a
    ld hl, $A000 + 255 * 2
    ld de, wName2
    ld b, 16
.c: ld a, [hl+]
    ld [de], a
    inc de
    dec b
    jr nz, .c
    ld a, META_PAGE
    ld [$4000], a
    ld hl, $B000
    ld de, wPlay
    ld b, 32
.p: ld a, [hl+]
    ld [de], a
    inc de
    dec b
    jr nz, .p
    ld a, $AA
    ld [wDone], a
.h: jr .h
SAladdin: db "Aladdin.gbc", 0
SNew:     db "Brand New.gb", 0
SECTION "vars", WRAM0[$C000]
wRes:   ds 8
wMarks: ds 18
wName2: ds 16
wPlay:  ds 32
wDone:  ds 1
