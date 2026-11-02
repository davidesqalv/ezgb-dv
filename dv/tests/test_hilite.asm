; HighlightRow / UnhighlightRow (bank2_hilite.asm) on a pattern in VRAM, with the
; LCD on (VramSync waits for the PPU's modes, as on the console):
;   list row 1 (y 32) HighlightRow, row 2 (y 44) UnhighlightRow, and row 3 (y 56),
;   which run.py makes plain-shaped, HighlightRow then UnhighlightRow
; and BlitCol1Hook (blit_col1's frame: src, addr, n, xm) with hBarBlit set:
;   Src12 into list row 5 (y 80), tile column 3 with xm 0 and column 7 with xm $FF;
; then with hBarBlit clear, which goes on to blit_col1 + 3 (a recorder here:
; c, hl and sp to wRec).
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
    ld a, $AA
    ld [$C000], a
.h: jr .h
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
