; HighlightRow / UnhighlightRow (bank2_hilite.asm) on a pattern in VRAM, with the
; LCD on (VramSync waits for the PPU's modes, as on the console):
;   list row 1 (y 32) HighlightRow, row 2 (y 44) UnhighlightRow, and row 3 (y 56),
;   which run.py makes plain-shaped, HighlightRow then UnhighlightRow
; and BlitCol1Hook (blit_col1's frame: src, addr, n, xm) with hBarBlit set:
;   Src12 into list row 5 (y 80), tile column 3 with xm 0 and column 7 with xm $FF;
; then with hBarBlit clear, which goes on to blit_col1 + 3 (a recorder here:
; c, hl and sp to wRec); and Digits4 for 0, 7, 39, 416, 1000, 9999 (wDig, 5
; bytes each), CounterDigits in the far stub's frame for 39 and 416 (wCD).
INCLUDE "bank2_hilite.asm"
SECTION "rowtab", ROM0[$2FBB]
    INCBIN "gfxrowtable.bin"
INCLUDE "hilite_bar.inc"            ; BAR_COL3, BAR_COL7: run.py, from GfxRowTable
SECTION "src", ROM0[$1000]
Src12: db $00, $FF, $81, $7E, $3C, $C3, $18, $E7, $01, $80, $55, $AA
SECTION "rec", ROMX[$7D8C], BANK[2]
; blit_col1 + 3 stand-in: blit_col1 would go on with hl = sp + 7, c = xm
BlitRec:
    ld a, c
    ld [wRec], a
    ld a, l
    ld [wRec + 1], a
    ld a, h
    ld [wRec + 2], a
    ld hl, sp+0
    ld a, l
    ld [wRec + 3], a
    ld a, h
    ld [wRec + 4], a
    ret
SECTION "rec_ram", WRAM0[$C010]
wRec: ds 5
SECTION "dig_ram", WRAM0[$C020]
wDig: ds 30
SECTION "cd_ram", WRAM0[$C040]
wCD: ds 10
SECTION "pattern", ROMX[$4000], BANK[1]
Pattern: INCBIN "hilite_vram.bin"          ; $1800 bytes for $8000-$97FF
SECTION "hdr", ROM0[$100]
    nop
    jp Main
    ds $150 - @, 0
SECTION "main", ROM0[$150]
Main:
    di
    ld sp, $DFF0
    xor a
    ldh [$FFFF], a                  ; no interrupts
.v: ldh a, [$FF44]
    cp 145
    jr nz, .v
    xor a
    ldh [$FF40], a                  ; LCD off to load the pattern
    ld a, 1
    ld [$2000], a
    ld hl, Pattern
    ld de, $8000
    ld bc, $1800
.c: ld a, [hl+]
    ld [de], a
    inc de
    dec bc
    ld a, b
    or c
    jr nz, .c
    ld a, 2
    ld [$2000], a                   ; bank 2: the routines
    ld a, $91
    ldh [$FF40], a                  ; LCD on, BG on, tiles at $8000
    ld a, 32
    call .hi
    ld a, 44
    call .un
    ld a, 56
    call .hi
    ld a, 56
    call .un
    ld a, 1
    ldh [$FFF3], a                  ; hBarBlit
    ld de, $000C                    ; xm 0, n 12
    ld bc, BAR_COL3
    call .blit
    ld de, $FF0C                    ; xm $FF, n 12
    ld bc, BAR_COL7
    call .blit
    xor a
    ldh [$FFF3], a
    ld de, $5A0C                    ; xm $5A: on to blit_col1
    ld bc, BAR_COL3
    call .blit
    ld hl, .digcases
    ld de, wDig
.dig:
    ld a, [hl+]
    ld c, a
    ld a, [hl+]
    ld b, a                         ; bc = n
    cp $FF
    jr z, .digdone
    push hl
    push de
    push de                         ; buf
    push bc                         ; n
    call Digits4
    add sp, 4
    pop de
    ld hl, 5
    add hl, de
    ld d, h
    ld e, l
    pop hl
    jr .dig
.digdone:
    ld bc, 39
    ld de, wCD
    call .cd
    ld bc, 416
    ld de, wCD + 5
    call .cd
    ld a, $AA
    ld [$C000], a
.h: jr .h
.cd:                                ; CounterDigits(3 pads, u32 bc, de, radix 10)
    ld hl, 10
    push hl                         ; radix
    push de                         ; buf
    ld hl, 0
    push hl                         ; v, high half
    push bc                         ; v, low half
    push hl
    push hl
    push hl                         ; three pads
    call CounterDigits
    add sp, 14
    ret
.digcases
    dw 0, 7, 39, 416, 1000, 9999, $FFFF
.blit:                              ; BlitCol1Hook(Src12, bc, e, d)
    push de
    push bc
    ld hl, Src12
    push hl
    call BlitCol1Hook
    add sp, 6
    ret
.hi:
    push af
    inc sp
    call HighlightRow
    inc sp
    ret
.un:
    push af
    inc sp
    call UnhighlightRow
    inc sp
    ret
