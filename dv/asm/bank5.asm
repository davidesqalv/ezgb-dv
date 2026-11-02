; Bank 5 additions for the ezjr custom build (free space after FatFs).
;   05:7680  ShiftRows: move drawn list rows in VRAM for a one-row scroll
;   05:7962  ezjr_scroll_down / ezjr_scroll_up (C, ezjr_scroll_7962.bin, INCBIN'd)
;   (TabNumFar, the "n/total" counter, sat at 05:7b9f; it is in bank2_tabnum.asm now)

DEF ENTRY_COUNT EQU $c2a2

DEF GfxRowTable EQU $2fbb           ; 00: pixel row -> VRAM address of its tile column 0

SECTION "vrammove", ROMX[$7680], BANK[5]
; ShiftRows(dst_y, src_y, batches, step), sdcccall 0, u8 arguments at sp+2..5:
; copies `batches` groups of 4 canvas pixel rows, all 20 tile columns, from
; src_y to dst_y (both multiples of 4, so a group is 8 bytes inside one tile
; and never crosses a tile boundary), then steps both by `step`: 4, or -4 to
; copy bottom first when moving rows down so nothing is overwritten before it
; is read. A one-row scroll moves the rows that stay on screen this way and
; leaves only two rows to draw (ezjr_scroll.c), instead of all ten.
;
; Each group goes out in one VRAM window, synced exactly like draw12.c's
; blit_col1 (see the long comment there): a fresh HBlank (mode 3, then mode
; 0) with interrupts off, or straight away while LY reads 144..151 in mode 1;
; a sync from LY >= 143 waits with interrupts on for LY 145..150 or the next
; frame, so the VBlank callback that points the BG tile data back at $8000
; is never delayed. The group is two passes of 4 bytes: 57 M-cycles, inside
; the 51 + 20 that blit_col1 relies on.
ShiftRows::
.batch
    ld hl, sp+3                      ; src_y
    ld a, [hl]
    call RowAddr
    push hl
    ld hl, sp+4                      ; dst_y (the push moved sp)
    ld a, [hl]
    call RowAddr
    ld d, h
    ld e, l
    pop hl
    ld b, 20                        ; tile columns
.col
    di
    ldh a, [$ff41]
    and 3
    cp 1
    jr nz, .sync
    ldh a, [$ff44]
    cp 144
    jr c, .sync
    cp 152
    jr nc, .sync
    jr .go
.sync
    ldh a, [$ff44]
    cp 143
    jr c, .m3
    ei
.vb
    ldh a, [$ff44]
    cp 143
    jr c, .col
    cp 145
    jr c, .vb
    cp 151
    jr c, .col
    jr .vb
.m3
    ldh a, [$ff41]
    and 3
    cp 3
    jr nz, .m3
.w0
    ldh a, [$ff41]
    and 3
    jr nz, .w0
.go
    ld c, 2
.half
    REPT 4
    ld a, [hl+]
    ld [de], a
    inc de
    ENDR
    dec c
    jr nz, .half
    ei
    ld a, l                         ; next tile column: 16 on, 8 of them done
    add 8
    ld l, a
    jr nc, .src
    inc h
.src
    ld a, e
    add 8
    ld e, a
    jr nc, .dst
    inc d
.dst
    dec b
    jr nz, .col
    ld hl, sp+5                      ; step
    ld c, [hl]
    dec hl                          ; batches
    dec [hl]
    ret z
    dec hl                          ; src_y
    ld a, [hl]
    add c
    ld [hl-], a                     ; dst_y
    ld a, [hl]
    add c
    ld [hl], a
    jp .batch

SECTION "scroll", ROMX[$7962], BANK[5]
    INCBIN "ezjr_scroll_7962.bin"

; ---------------------------------------------------------------------------
; SORT TOP and play counts.
;
; Play table: pSRAM page $11 ("EZJR" at $B104 once initialized) (battery-backed meta page, free from $A400 up,
; docs/psram-page-map.md) at $B000: 64 entries of [hash lo, hash hi, count,
; flags]; flags bit 7 = valid ($80), bit 0 = starred. Sort mode record at
; $B100: 'S', 'G', 1, $FE = A-Z (the SET tab's "SORT A-Z" box, flcfg's old
; SGB BOOT record moved here); anything else = TOP.
; Score = 255 for a starred game, else min(254, base + 12 * plays) under
; TOP, or 0 under A-Z (stars still pinned, the rest by name); base comes
; from RankTable (ranking.txt).

DEF RAM_BANK    EQU $4000
DEF PLAY_TABLE  EQU $B000
DEF PLAY_SLOTS  EQU 64
DEF SORT_REC    EQU $B100
DEF TABLE_MAGIC EQU $B104
IF !DEF(META_PAGE)
DEF META_PAGE EQU $11
ENDC
IF !DEF(KEY_PAGE)
DEF KEY_PAGE EQU $1F
ENDC
IF !DEF(REC_PAGE0)
DEF REC_PAGE0 EQU $12
ENDC
DEF LAUNCH_PATH EQU $C2A6
DEF F_VALID     EQU $80
DEF F_STAR      EQU $01
DEF PLAY_POINTS EQU 12

SECTION "top", ROMX[$7C43], BANK[5]

; Hash: de = NUL-terminated name in the current window/WRAM -> hl = 16-bit
; djb2 of the uppercased bytes. Clobbers a, bc, de.
Hash::
    ld hl, 5381
.next:
    ld a, [de]
    inc de
    and a
    ret z
    cp $61
    jr c, .mix
    cp $7B
    jr nc, .mix
    sub $20
.mix:
    ld b, h
    ld c, l
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl                      ; * 32
    add hl, bc                      ; * 33
    add a, l
    ld l, a
    ld a, h
    adc 0
    ld h, a
    jr .next

; FindPlay: hl = hash, page $11 mapped -> hl = its entry (carry clear), or
; carry set and hl = a free entry ($0000 if none). Clobbers a, bc, de.
FindPlay:
    ld a, [TABLE_MAGIC]             ; first use on this cart, or the cell lost power:
    cp $45                          ; start an empty table ("EZJR" at $B104)
    jr nz, .init
    ld a, [TABLE_MAGIC + 1]
    cp $5A
    jr nz, .init
    ld a, [TABLE_MAGIC + 2]
    cp $4A
    jr nz, .init
    ld a, [TABLE_MAGIC + 3]
    cp $52
    jr z, .ready
.init:
    push hl
    ld hl, PLAY_TABLE
    xor a
    ld b, a                         ; 256 bytes
.zero:
    ld [hl+], a
    dec b
    jr nz, .zero
    ld hl, TABLE_MAGIC
    ld [hl], $45
    inc hl
    ld [hl], $5A
    inc hl
    ld [hl], $4A
    inc hl
    ld [hl], $52
    pop hl
.ready:
    ld d, h
    ld e, l                         ; de = hash
    ld hl, PLAY_TABLE
    ld bc, 0                        ; first free entry
    ld a, PLAY_SLOTS
.scan:
    push af
    inc hl
    inc hl
    inc hl
    ld a, [hl-]                     ; flags
    dec hl
    dec hl
    and F_VALID
    jr z, .free
    ld a, [hl+]
    cp e
    jr nz, .missLo
    ld a, [hl-]
    cp d
    jr nz, .miss
    pop af                          ; found: carry clear
    and a
    ret
.missLo:
    dec hl
    jr .miss
.free:
    ld a, b
    or c
    jr nz, .miss
    ld b, h
    ld c, l
.miss:
    ld a, l
    add a, 4
    ld l, a
    ld a, h
    adc 0
    ld h, a
    pop af
    dec a
    jr nz, .scan
    ld h, b
    ld l, c
    scf
    ret

; IsAZ: page $11 mapped -> Z set when SORT A-Z is ticked ($B100 = 'S','G',1,$FE). Uses a only.
IsAZ:
    ld a, [SORT_REC]
    cp $53
    ret nz
    ld a, [SORT_REC + 1]
    cp $47
    ret nz
    ld a, [SORT_REC + 2]
    cp 1
    ret nz
    ld a, [SORT_REC + 3]
    cp $FE
    ret

; Score: hl = hash -> a = sort score. Maps page $11 (FPGA page 3 must be on).
Score:
    push hl
    ld b, h
    ld c, l                         ; bc = hash
    ld hl, RankTable
    ld a, [hl+]
    ld d, a                         ; games in the table
    ld e, 0                         ; base
.rank:
    ld a, d
    and a
    jr z, .ranked
    ld a, [hl+]
    cp c
    jr nz, .rskip
    ld a, [hl]
    cp b
    jr nz, .rskip
    inc hl
    ld e, [hl]
    jr .ranked
.rskip:
    inc hl
    inc hl
    dec d
    jr .rank
.ranked:
    pop hl                          ; hash
    ld a, META_PAGE
    ld [RAM_BANK], a
    ld d, 0                         ; d = 1 under SORT A-Z
    call IsAZ
    jr nz, .notAZ
    ld d, 1
    ld e, 0                         ; A-Z: no base score
.notAZ:
    push de                         ; e = base
    call FindPlay
    pop de
    jr c, .noplays
    inc hl
    inc hl
    ld a, [hl+]                     ; count
    ld c, a
    ld a, [hl]                      ; flags
    and F_STAR
    jr z, .plays
    ld a, 255                       ; starred: always on top
    ret
.plays:                             ; a = min(254, base + 12 * count)
    ld a, d
    and a
    jr z, .counted
    xor a                           ; A-Z: every unstarred game scores 0
    ret
.counted:
    ld a, c
    cp 21
    jr nc, .max                     ; 21 * 12 > 254
    ld b, a
    ld a, e
.add:
    ld c, a
    ld a, b
    and a
    ld a, c
    jr z, .sum
    add a, PLAY_POINTS
    jr c, .max
    dec b
    jr .add
.sum:
    cp 255
    ret c
.max:
    ld a, 254
    ret
.noplays:
    ld a, e
    ret

; ScoreKeys: far-called from BuildKeysTop (bank 8) after build_keys(n), with
; the sort's window set up (FPGA page 3). n is at sp+6. In TOP mode, each
; file key [class][13 name chars][idx] becomes [class][~score][12 chars][idx];
; directories keep their name order.
ScoreKeys::
    ld hl, sp+6
    ld a, [hl+]
    ld c, a
    ld b, [hl]                      ; bc = n
    ld de, 0                        ; i
.key:
    ld a, e
    cp c
    jr nz, .go
    ld a, d
    cp b
    ret z
.go:
    push bc
    push de
    ld a, KEY_PAGE
    ld [RAM_BANK], a
    ld h, d
    ld l, e
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl
    ld bc, $A000
    add hl, bc                      ; hl = key
    ld a, [hl]
    and a
    jr z, .done                     ; class 0: a directory
    push hl
    ld bc, 14
    add hl, bc
    ld a, [hl+]
    ld h, [hl]
    ld l, a                         ; hl = record index
    ld a, l
    rlca
    rlca
    rlca
    and 7                           ; idx >> 5 (idx < 512)
    bit 0, h
    jr z, .lo
    add a, 8
.lo:
    add a, REC_PAGE0
    ld [RAM_BANK], a
    ld a, l
    and 31                          ; slot
    ld e, a
    ld d, a                         ; de = slot * 256
    ld a, 0
    sub e
    ld e, a
    ld a, d
    sbc 0
    ld d, a                         ; - slot = slot * 255
    ld hl, $A000
    add hl, de
    ld d, h
    ld e, l                         ; de = record name
    call Hash
    call Score                      ; a = score
    cpl                             ; high scores sort first
    ld c, a
    ld a, KEY_PAGE
    ld [RAM_BANK], a
    pop hl                          ; key
    push hl
    ld de, 12
    add hl, de                      ; &key[12]
    ld b, 12
.shift:                             ; key[j] = key[j - 1], j = 13..2
    ld a, [hl+]
    ld [hl-], a
    dec hl
    dec b
    jr nz, .shift
    pop hl
    inc hl
    ld [hl], c                      ; key[1] = ~score
.done:
    pop de
    pop bc
    inc de
    jr .key

; PlayCount: far-called on every launch (LastRomPersist's tail). Hashes the
; basename of the path at $C2A6 and adds one play in page $11.
PlayCount::
    ld hl, LAUNCH_PATH
    ld d, h
    ld e, l
.base:
    ld a, [hl+]
    and a
    jr z, .hash
    cp $2F                          ; "/"
    jr nz, .base
    ld d, h
    ld e, l
    jr .base
.hash:
    call Hash                       ; hl = hash of the basename
    push hl
    call MapMeta
    pop hl
    push hl
    call FindPlay
    pop de                          ; de = hash
    jr nc, .bump
    ld a, h
    or l
    jr z, .unmap                    ; table full: skip
    ld a, e
    ld [hl+], a
    ld a, d
    ld [hl+], a
    xor a
    ld [hl+], a                     ; count 0
    ld [hl], F_VALID
    dec hl
    dec hl
    dec hl
.bump:
    inc hl
    inc hl
    ld a, [hl]
    inc a
    jr z, .unmap                    ; saturate at 255
    ld [hl], a
.unmap:
    jp UnmapMeta

; MapMeta / UnmapMeta: page $11 under FPGA page 3, the way flcfg's sgb_get/set do.
MapMeta::
    ld a, META_PAGE
    ld [RAM_BANK], a
    ld a, 3
    jr SetFpgaPage
UnmapMeta::
    xor a
    ld [RAM_BANK], a
SetFpgaPage:
    ld hl, $7F00
    ld [hl], $E1
    ld l, $10
    ld [hl], $E2
    ld l, $20
    ld [hl], $E3
    ld l, $C0
    ld [hl], a
    ld l, $F0
    ld [hl], $E4
    ret


; ---------------------------------------------------------------------------
; Stars. StarQuery / StarToggle are far-called from the hold-A menu (rom_menu.c)
; through bank-0 stubs; the ROM's name is in NAME_BUF ($C4A4). Result in E.
; MarkStars runs after every sort (the bank-0 ResortStub): it writes $5A into
; byte 252 of each starred file's record (after the name's NUL, which only a
; 252-byte name would reach) and 0 elsewhere; DrawNameWithIcon draws a star
; icon (glyph $7F) for a record marked $5A.

DEF NAME_BUF   EQU $C4A4
DEF STAR_MARK  EQU $5A

SECTION "rowaddr", ROMX[$7E1D], BANK[5]
; a = pixel row -> hl = its VRAM address in tile column 0. Clobbers bc.
; ShiftRows' helper, between the TOP block and the stars.
RowAddr:
    ld l, a
    ld h, 0
    add hl, hl
    ld bc, GfxRowTable
    add hl, bc
    ld a, [hl+]
    ld h, [hl]
    ld l, a
    ret

SECTION "stars", ROMX[$7E29], BANK[5]
StarQuery::
    ld de, NAME_BUF
    call Hash
    push hl
    call MapMeta
    pop hl
    call FindPlay
    ld e, 0
    jr c, .out
    inc hl
    inc hl
    inc hl
    ld a, [hl]
    and F_STAR
    ld e, a
.out:
    push de
    call UnmapMeta
    pop de
    ret

StarToggle::
    ld de, NAME_BUF
    call Hash
    push hl
    call MapMeta
    pop hl
    push hl
    call FindPlay
    pop de                          ; hash
    jr nc, .have
    ld a, h
    or l
    jr z, .full
    ld a, e
    ld [hl+], a
    ld a, d
    ld [hl+], a
    xor a
    ld [hl+], a
    ld [hl], F_VALID
    dec hl
    dec hl
    dec hl
.have:
    inc hl
    inc hl
    inc hl
    ld a, [hl]
    xor F_STAR
    ld [hl], a
    and F_STAR
    ld e, a
    jr .done
.full:
    ld e, 0
.done:
    push de
    call UnmapMeta
    pop de
    ret

MarkStars::
    ld a, [ENTRY_COUNT]
    ld c, a
    ld a, [ENTRY_COUNT + 1]
    ld b, a
    ld de, 0
.rec:
    ld a, e
    cp c
    jr nz, .go
    ld a, d
    cp b
    jr z, .end
.go:
    push bc
    push de
    ld a, e
    rlca
    rlca
    rlca
    and 7
    bit 0, d
    jr z, .b0
    add a, 8
.b0:
    add a, REC_PAGE0
    ld [RAM_BANK], a
    push af                         ; record bank
    ld a, e
    and 31
    ld e, a
    ld d, a
    ld a, 0
    sub e
    ld e, a
    ld a, d
    sbc 0
    ld d, a                         ; slot * 255
    ld hl, $A000
    add hl, de
    push hl                         ; record
    ld de, 254
    add hl, de
    ld a, [hl]
    cp $10
    jr z, .skip                     ; a directory
    pop hl
    push hl
    ld b, 252
.len:
    ld a, [hl+]
    and a
    jr z, .short
    dec b
    jr nz, .len
    jr .skip                        ; a 252-byte name: no room for the mark
.short:
    pop de
    push de                         ; de = record name
    call Hash
    ld a, META_PAGE
    ld [RAM_BANK], a
    call FindPlay
    ld c, 0
    jr c, .flag
    inc hl
    inc hl
    inc hl
    ld a, [hl]
    and F_STAR
    jr z, .flag
    ld c, STAR_MARK
.flag:
    pop hl                          ; record
    pop af                          ; its bank
    ld [RAM_BANK], a
    ld de, 252
    add hl, de
    ld [hl], c
    jr .next
.skip:
    pop hl
    pop af
.next:
    pop de
    pop bc
    inc de
    jr .rec
.end:
    ld a, REC_PAGE0
    ld [RAM_BANK], a
    ret

; RankTable: count, then [hash lo, hash hi, base] per ranked game (ranking.txt).
; Its own section so it can grow: 256 bytes = 85 games.
SECTION "ranktab", ROMX[$7F00], BANK[5]
RankTable::
    INCBIN "rank_table.bin"
