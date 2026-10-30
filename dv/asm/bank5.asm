; Bank 5 additions for the ezjr custom build (free space after FatFs).
;   05:7962  ezjr_scroll_down / ezjr_scroll_up (C, ezjr_scroll_7962.bin, INCBIN'd)
;   05:7b00  TabNumFar: the list position as "n/total" in green, right-aligned
;            (TabNum12 at 00:0380 becomes a far stub to it)

DEF FarCallDrawString12 EQU $05c0
DEF wDrawColor  EQU $d734
DEF wDrawColorB EQU $d735
DEF ENTRY_COUNT EQU $c2a2
DEF COUNTER_X   EQU 118             ; 7 glyphs x 6 px, ending at x 160

SECTION "scroll", ROMX[$7962], BANK[5]
    INCBIN "ezjr_scroll_7962.bin"

SECTION "tabnum", ROMX[$7B00], BANK[5]
; Called through a far stub with DrawString's frame: three pads, then
; s (u16, the stock "n" digits), len, x, y. Draws "  n/total" in ink 1.
TabNumFar::
    add sp, -12                     ; buf[12]: s now at sp+20
    ld a, [wDrawColor]
    ld b, a
    ld a, [wDrawColorB]
    ld c, a
    push bc                         ; saved draw state; buf at sp+2, s at sp+22
    ld hl, sp+22
    ld a, [hl+]
    ld e, a
    ld d, [hl]                      ; de = s
    ld hl, sp+2                     ; buf
    call FormatCounter
    ld a, 1
    ld [wDrawColor], a              ; green
    xor a
    ld [wDrawColorB], a             ; on black
    ld hl, (0 << 8) | COUNTER_X     ; row 0, col x
    push hl
    xor a
    push af
    inc sp                          ; len 0: to the NUL
    ld hl, sp+5                     ; buf
    push hl
    call FarCallDrawString12
    add sp, 5
    pop bc
    ld a, b
    ld [wDrawColor], a
    ld a, c
    ld [wDrawColorB], a
    add sp, 12
    ret

; FormatCounter: hl = 8-byte buffer, de = the stock number text (digits, maybe
; padded, up to 4 chars or a NUL). Writes "  n/total" right-aligned in 7 glyphs
; plus a NUL, total from ENTRY_COUNT.
FormatCounter::
    push hl                         ; buf
    push de                         ; s
    ld a, $20
    ld b, 7
.fill:
    ld [hl+], a
    dec b
    jr nz, .fill
    xor a
    ld [hl], a                      ; buf[7] = NUL
    dec hl                          ; &buf[6]
    ld a, [ENTRY_COUNT]
    ld e, a
    ld a, [ENTRY_COUNT + 1]
    ld d, a
    call PutDec                     ; total, right to left
    ld [hl], $2F                    ; "/"
    dec hl
    ld b, h
    ld c, l                         ; bc = where n ends
    pop hl                          ; s
    push bc
    ld de, 0
    ld b, 4
.parse:
    ld a, [hl+]
    and a
    jr z, .parsed
    sub $30
    cp 10
    jr nc, .skip                    ; spaces and anything else
    push hl
    push bc
    ld c, a
    ld h, d
    ld l, e
    add hl, hl
    ld d, h
    ld e, l
    add hl, hl
    add hl, hl
    add hl, de                      ; value * 10
    ld a, l
    add a, c
    ld e, a
    ld a, h
    adc 0
    ld d, a                         ; + digit
    pop bc
    pop hl
.skip:
    dec b
    jr nz, .parse
.parsed:
    pop hl                          ; where n ends
    call PutDec
    pop hl                          ; buf
    ret

; PutDec: de = value, hl = where its last digit goes; writes the digits right
; to left and returns hl just left of the first one.
PutDec:
.digit:
    push hl
    ld hl, 0                        ; quotient
.div:
    ld a, e
    sub 10
    ld c, a
    ld a, d
    sbc 0
    jr c, .rem
    ld d, a
    ld e, c
    inc hl
    jr .div
.rem:
    ld a, e
    add a, $30
    ld b, a
    ld d, h
    ld e, l                         ; de = quotient
    pop hl
    ld [hl], b
    dec hl
    ld a, d
    or e
    jr nz, .digit
    ret

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

SECTION "top", ROMX[$7BB0], BANK[5]

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

SECTION "stars", ROMX[$7E10], BANK[5]
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
