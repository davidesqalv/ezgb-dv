; FW5 fast load only on FPGA re-creations of the Game Boy Color (ModRetro Chromatic).
; Called from SetFpga7FD4 (01:480b) in place of its first instruction, ld hl,$7F00.
; Writes the fast-load key into the function's argument byte, [sp+8] here:
;   $11 = fast load (the FW5 loader skips its pause after every SD read), $00 = stock pause.
; A real Game Boy Color keeps writes to $FEA0 (RAM on CGB-D and earlier, a fixed nonzero
; pattern on CGB-E). The Chromatic reads $00 there whatever is written. An original
; Game Boy also reads $00, so the CGB-only register $FF72 is checked first.
; Any misread (OAM locked: $FF) falls on the slow, safe side.
SECTION "detect", ROM0[$0]
Detect:
    ld a, $5A
    ldh [$FF72], a
    ldh a, [$FF72]
    cp $5A
    jr nz, .slow                    ; no CGB registers: DMG, MGB or SGB
    ldh a, [$FF40]
    bit 7, a
    jr z, .test                     ; LCD off: OAM area accessible
.vblank:
    ldh a, [$FF41]
    and 3
    cp 1
    jr nz, .vblank
.test:
    ld a, $5A
    ld [$FEA0], a
    ld a, [$FEA0]
    and a
    jr nz, .slow
    ld a, $A5
    ld [$FEA0], a
    ld a, [$FEA0]
    and a
    jr nz, .slow
    ld a, $11                       ; reads back $00 both times: Chromatic
    jr .store
.slow:
    xor a
.store:
    ld hl, sp + 8
    ld [hl], a
    ld hl, $7F00                    ; the instruction the call replaced
    ret
