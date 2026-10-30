; Bank 8 changes for the ezjr custom build.
;
; MsgBox12 (08:7e80, grows into the free space after it, up to 08:7fff):
;   the Reading / Loading / Error box, Pokemon-style: black inside, a white frame
;   (2 px outer line, 1 px gap, 1 px inner line, rounded outer corners), white text.
; HelpLine (08:7db1, Help12's line(s, n, y) helper): same job with a 26-byte buffer,
;   so one HELP line can hold the whole "github.com/lukesau/ezgb".
; HelpCredit (08:7bd2, free space): the credit string for the HELP page.

DEF StoreDrawParams     EQU $2791   ; (u8 color, u8 colorB, u8 op)
DEF DrawRect            EQU $27ba   ; (x0, y0, x1, y1, fill): fill 1 = border ink + inside paper, 0 = outline
DEF FarCallDrawString12 EQU $05c0   ; (const u8 *s, u8 len, u8 col, u8 row)
DEF hClip12             EQU $fff9
DEF ReadingStr          EQU $7374
DEF LoadingStr          EQU $73af
DEF ErrorFileStr        EQU $73ea

DEF BX0 EQU 32
DEF BY0 EQU 54
DEF BX1 EQU 127
DEF BY1 EQU 89
DEF TEXT_X EQU 50                   ; 10 glyphs x 6 px, centered in the box
DEF TEXT_ROW EQU 66                 ; pixel row, the renderer rounds down to 64

MACRO SDP                           ; StoreDrawParams(ink, paper, 0)
    ld hl, (0 << 8) | (\2)
    push hl
    ld a, \1
    push af
    inc sp
    call StoreDrawParams
    add sp, 3
ENDM

MACRO RECT                          ; DrawRect(x0, y0, x1, y1, fill)
    ld a, \5
    push af
    inc sp
    ld hl, ((\4) << 8) | (\3)
    push hl
    ld hl, ((\2) << 8) | (\1)
    push hl
    call DrawRect
    add sp, 5
ENDM

SECTION "msgbox", ROMX[$7E80], BANK[8]
MsgBox12::                          ; (u8 which): 0 Reading, 1 Loading, 2 Error file
    add sp, -12                     ; buf[12]
    ld hl, sp+14
    ld a, [hl]
    ld de, ReadingStr
    and a
    jr z, .copy
    ld de, LoadingStr
    dec a
    jr z, .copy
    ld de, ErrorFileStr
.copy:                              ; the renderer runs in bank 2: copy the string to the stack
    ld hl, sp+0
    ld b, 10
.loop:
    ld a, [de]
    and a
    jr z, .term
    ld [hl+], a
    inc de
    dec b
    jr nz, .loop
.term:
    xor a
    ld [hl], a

    SDP 3, 0                                    ; white ink, black paper
    RECT BX0, BY0, BX1, BY1, 1                  ; black box, 1 px white border
    RECT BX0 + 1, BY0 + 1, BX1 - 1, BY1 - 1, 0  ; second outer line
    RECT BX0 + 3, BY0 + 3, BX1 - 3, BY1 - 3, 0  ; inner line
    SDP 0, 0
    RECT BX0, BY0, BX0, BY0, 0                  ; round the outer corners
    RECT BX1, BY0, BX1, BY0, 0
    RECT BX0, BY1, BX0, BY1, 0
    RECT BX1, BY1, BX1, BY1, 0

    SDP 3, 0                                    ; white text on black
    ld a, BX1 - 4
    ldh [hClip12], a                            ; keep the row's paper off the frame
    ld hl, (TEXT_ROW << 8) | TEXT_X
    push hl
    xor a
    push af
    inc sp                                      ; len 0: to the NUL
    ld hl, sp+3
    push hl                                     ; s = buf
    call FarCallDrawString12
    add sp, 5
    xor a
    ldh [hClip12], a
    SDP 0, 3                                    ; leave the draw state as the stock box does
    add sp, 12
    ret

SECTION "helpline", ROMX[$7DB1], BANK[8]
HelpLine::                          ; line(const u8 *s, u8 n, u8 y)
    add sp, -26
    ld hl, sp+28
    ld a, [hl+]
    ld e, a
    ld d, [hl]                      ; de = s
    ld hl, sp+30
    ld c, [hl]                      ; n
    ld hl, sp+0
.cp:
    ld a, c
    and a
    jr z, .z
    ld a, [de]
    ld [hl+], a
    inc de
    dec c
    jr .cp
.z:
    xor a
    ld [hl], a
    ld hl, sp+31
    ld h, [hl]                      ; row = y
    ld l, 4                         ; col = X0
    push hl
    xor a
    push af
    inc sp
    ld hl, sp+3
    push hl
    call FarCallDrawString12
    add sp, 5
    add sp, 26
    ret

SECTION "credit", ROMX[$7BD2], BANK[8]
HelpCredit::
    db "custom: davidesqalv", 0

; BuildKeysTop (08:7be6, free space after HelpCredit): the sort's `call
; build_keys` (08:7496) lands here. Runs build_keys(n), then far-calls
; ScoreKeys (bank 5) with n still pushed, which turns the keys into SORT TOP
; keys unless SORT A-Z is ticked.
DEF build_keys        EQU $778b
DEF FarCallTrampoline EQU $078d

SECTION "buildkeys", ROMX[$7BE6], BANK[8]
BuildKeysTop::
    ld hl, sp+2
    ld a, [hl+]
    ld h, [hl]
    ld l, a                         ; n
    push hl
    call build_keys
    call FarCallTrampoline          ; n is still on the stack: ScoreKeys reads it at sp+6
    dw SCOREKEYS
    db 5, 0
    add sp, 2
    ret
