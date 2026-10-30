INCLUDE "bank2_recolor.asm"
SECTION "dinest", ROM0[$06FD]
    di
    ld a, [$D6D0]
    inc a
    ld [$D6D0], a
    ret
SECTION "einest", ROM0[$0706]
    ld a, [$D6D0]
    dec a
    ld [$D6D0], a
    ret nz
    ei
    ret
SECTION "rowtab", ROM0[$2FBB]
    INCBIN "gfxrowtable.bin"
SECTION "hdr", ROM0[$100]
    nop
    jp Main
    ds $150 - @, 0
SECTION "main", ROM0[$150]
Main:
    di
    ld sp, $DFF0
    xor a
    ld [$D6D0], a
.v: ldh a, [$FF44]
    cp 145
    jr nz, .v
    xor a
    ldh [$FF40], a                  ; LCD off: VRAM always open
    ld hl, $8000
    ld bc, $1800
.f: ld a, $FF
    ld [hl+], a
    dec bc
    ld a, b
    or c
    jr nz, .f
    ld a, 2
    ld [$2000], a
    ld a, 32                        ; list row 1: y = 20 + 12
    push af
    inc sp
    call RecolorIcon
    inc sp
    ld a, $AA
    ld [$C000], a
.h: jr .h
