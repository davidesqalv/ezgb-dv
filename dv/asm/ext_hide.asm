; Hide a trailing .gb/.gbc in 12px text (ezjr custom build), bank 2 free space at $43D0.
;
; Fit12Vis:  DrawString12's layout call (its `call Fit12` is pointed here): lays out
;            the string without a trailing .gb/.gbc, so list rows, the scrolling
;            name and the last-ROM box never show the extension.
; Fit12Marq: MarqueeWidth12's fit test (its far call to Fit12 is pointed here): when
;            every visible glyph fits it returns the full length, hidden extension
;            included, so a name that only overflows by its extension does not scroll.
;
; Both keep Fit12's frame (sdcccall 0): ret, pad, pad, s (u16), len (u8), col (u8),
; xs (u16); the u8 result is in E.

DEF Fit12 EQU $7100

SECTION "ext_hide", ROMX[$43D0], BANK[2]

Fit12Vis::
    call VisLen             ; A = len to lay out
    ld hl, sp+9
    ld d, [hl]              ; col
    ld e, a                 ; len
    ld hl, sp+10
    ld a, [hl+]
    ld h, [hl]
    ld l, a
    push hl                 ; xs
    push de                 ; len, col
    ld hl, sp+10
    ld a, [hl+]
    ld h, [hl]
    ld l, a
    push hl                 ; s
    ld hl, 0
    push hl                 ; pads
    push hl
    call Fit12
    add sp, 10
    ret

Fit12Marq::
    call VisLen             ; A = len to lay out, B = full length, C = 1 if hidden
    push bc
    push af                 ; [sp+1] = visible len
    ld hl, sp+13
    ld d, [hl]              ; col
    ld e, a
    ld hl, sp+14
    ld a, [hl+]
    ld h, [hl]
    ld l, a
    push hl                 ; xs
    push de                 ; len, col
    ld hl, sp+14
    ld a, [hl+]
    ld h, [hl]
    ld l, a
    push hl                 ; s
    ld hl, 0
    push hl
    push hl
    call Fit12              ; E = glyphs placed
    add sp, 10
    pop af                  ; A = visible len
    pop bc
    ld d, a
    ld a, c
    and a
    ret z                   ; nothing hidden: Fit12's answer
    ld a, e
    cp d
    ret nz                  ; cut by the row edge: Fit12's answer
    ld e, b                 ; all visible glyphs placed: report the full length
    ret

; In: the wrapper's frame (s at sp+8, len at sp+10 here). Out: A = len to use,
; B = string length (to the NUL or the cap), C = 1 if a .gb/.gbc was cut off.
VisLen:
    ld hl, sp+10
    ld a, [hl]
    ld c, a                 ; caller's len
    and a
    jr z, .cap40
    cp 41
    jr c, .capOk
.cap40:
    ld a, 40
.capOk:
    ld d, a                 ; cap
    ld hl, sp+8
    ld a, [hl+]
    ld h, [hl]
    ld l, a                 ; s
    ld b, 0                 ; i
    ld e, $FF               ; last dot
.scan:
    ld a, b
    cp d
    jr nc, .keep            ; no NUL within the cap: the end is not in view
    ld a, [hl+]
    and a
    jr z, .atEnd
    cp $2E                 ; "."
    jr nz, .next
    ld e, b
.next:
    inc b
    jr .scan
.atEnd:
    ld a, e
    inc a
    jr z, .keep             ; no dot
    dec a
    jr z, .keep             ; dot first: keep the name
    ld hl, sp+8
    ld a, [hl+]
    ld h, [hl]
    ld l, a
    ld a, e
    add a, l
    ld l, a
    ld a, h
    adc 0
    ld h, a
    inc hl                  ; s[dot + 1]
    ld a, [hl+]
    and $DF
    cp $47                 ; "G"
    jr nz, .keep
    ld a, [hl+]
    and $DF
    cp $42                 ; "B"
    jr nz, .keep
    ld a, b
    sub e                   ; length - dot: 3 for .gb, 4 for .gbc
    cp 3
    jr z, .hide
    cp 4
    jr nz, .keep
    ld a, [hl]
    and $DF
    cp $43                 ; "C"
    jr nz, .keep
.hide:
    ld a, e
    ld c, 1
    ret
.keep:
    ld a, c
    ld c, 0
    ret
