; RecolorIcon (02:6d60, after DrawNameWithIcon in the room Tamzen's metrics left):
; after a normal row is drawn in one pass (white icon + white name), turn the
; icon's pixels blue: ink 3 -> ink 2 is plane 0 cleared. The icon sits at
; x 1..8: tile column 0 (plane 0 byte = 0) and bit 7 of tile column 1.
; One DiNest/EiNest window per pixel row, right after a STAT check, as
; draw12.c's vram_rmw2 does (11 M-cycles inside the window).
DEF GfxRowTable EQU $2fbb           ; pixel row -> VRAM address of tile column 0
DEF DiNest      EQU $06fd           ; clobbers a only
DEF EiNest      EQU $0706           ; clobbers a only

SECTION "recolor", ROMX[$6D60], BANK[2]
RecolorIcon::                       ; (u8 py): rows py .. py + 11
    ld hl, sp+2
    ld c, [hl]
    ld b, 12
.row:
    ld l, c
    ld h, 0
    add hl, hl
    ld de, GfxRowTable
    add hl, de
    ld a, [hl+]
    ld h, [hl]
    ld l, a                         ; tile column 0, pixel row c
    ld de, 16
    call DiNest
.wait:
    ldh a, [$FF41]
    bit 1, a
    jr nz, .wait
    xor a
    ld [hl], a                      ; column 0, plane 0
    add hl, de
    ld a, [hl]
    and $7F
    ld [hl], a                      ; column 1, plane 0, x = 8
    call EiNest
    inc c
    dec b
    jr nz, .row
    ret
