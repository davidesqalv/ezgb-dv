DEF META_PAGE EQU 1
DEF REC_PAGE0 EQU 2
DEF KEY_PAGE EQU 15
INCLUDE "bank5.asm"

SECTION "data", ROMX[$4000], BANK[6]
TTable: INCBIN "t_table.bin"
TRecs:  INCBIN "t_recs.bin"
TRecsEnd:
TKeys:  INCBIN "t_keys.bin"
TKeysEnd:

SECTION "hdr", ROM0[$100]
    nop
    jp Main
    ds $150 - @, 0
SECTION "main", ROM0[$150]
MACRO COPY6                         ; copy from bank-6 data (\1, len \2) to RAM page \3 at \4
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
MACRO SAVEKEYS                      ; copy 96 key bytes from page 15 to WRAM \1
    ld a, KEY_PAGE
    ld [$4000], a
    ld hl, $A000
    ld de, \1
    ld b, 96
.s\@:
    ld a, [hl+]
    ld [de], a
    inc de
    dec b
    jr nz, .s\@
ENDM
MACRO SCORE
    ld a, 5
    ld [$2000], a
    ld hl, 6
    push hl
    ld hl, 0
    push hl
    push hl
    call ScoreKeys
    add sp, 6
ENDM
Main:
    di
    ld sp, $DFF0
    ld a, $0A
    ld [$0000], a                   ; RAM enable
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
    ld a, META_PAGE
    ld [$4000], a
    xor a
    ld [$B100], a                   ; no A-Z record: TOP
    COPY6 TRecs, TRecsEnd - TRecs, REC_PAGE0, $A000
    COPY6 TKeys, TKeysEnd - TKeys, KEY_PAGE, $A000
    SCORE
    SAVEKEYS wTop
    ; A-Z: record 'S','G',1,$FE
    COPY6 TKeys, TKeysEnd - TKeys, KEY_PAGE, $A000
    ld a, META_PAGE
    ld [$4000], a
    ld hl, $B100
    ld [hl], $53
    inc hl
    ld [hl], $47
    inc hl
    ld [hl], 1
    inc hl
    ld [hl], $FE
    SCORE
    SAVEKEYS wAZ
    ; launches
    ld a, 5
    ld [$2000], a
    ld hl, PathTetris
    call SetPath
    call PlayCount
    call PlayCount
    ld hl, PathNew
    call SetPath
    call PlayCount
    ld a, META_PAGE
    ld [$4000], a
    ld hl, $B000
    ld de, wPlay
    ld b, 64
.p: ld a, [hl+]
    ld [de], a
    inc de
    dec b
    jr nz, .p
    ld a, $AA
    ld [wDone], a
.h: jr .h
SetPath:
    ld de, $C2A6
.c: ld a, [hl+]
    ld [de], a
    inc de
    and a
    jr nz, .c
    ret
PathTetris: db "/Tetris DX.gbc", 0
PathNew:    db "/sub/New Game.gb", 0

SECTION "vars", WRAM0[$C000]
wTop:  ds 96
wAZ:   ds 96
wPlay: ds 64
wDone: ds 1
