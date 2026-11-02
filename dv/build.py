#!/usr/bin/env python3
"""Build ezgb-dv: lukesau's mod 6.9 for the EZ-Flash Junior 1.05e-0918 kernel,
plus my changes (see README.md).

    python3 dv/build.py                     # -> dv/build/ezgb-dv.dat
    python3 dv/build.py --stock ezgb.dat    # also writes the IPS patch for that
                                            # stock 1.05e-0918 kernel and checks it

Needs RGBDS (rgbasm, rgblink, rgbfix) and SDCC 4.6+. The build needs no
EZ-Flash file: scripts/build-kernel.sh reassembles mod 6.9 from the committed
disassembly and checks it against the manifest md5. Every patch checks the
bytes it replaces and stops if they differ.
"""
import argparse
import hashlib
import os
import subprocess
import sys
import tempfile

DV = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(DV)
BUILD = os.path.join(DV, "build")
ASM = os.path.join(DV, "asm")
VER = "1.05e-0918"
MOD_MD5 = "fa59648b4e9b1a23b4a10bdd31934adf"          # mod 6.9 for 1.05e-0918 (patches/kernel/manifest.json)
STOCK_MD5 = "5238ac5987d23b68a19d40e43af8c786"        # EZ-Flash's ezgb.dat 1.05e-0918

sys.path.insert(0, os.path.join(DV, "tools"))
sys.path.insert(0, os.path.join(REPO, "kernel", "tools"))
import bdf          # noqa: E402
import icons        # noqa: E402
import rank_table   # noqa: E402
from sdcc_build import compile_c, parse_ihx   # noqa: E402


def off(bank, addr):
    return bank * 0x4000 + (addr - (0x4000 if bank else 0))


def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode:
        raise SystemExit(f"{' '.join(cmd)} failed:\n{r.stdout}{r.stderr}")
    return r.stdout


# ---------------------------------------------------------------- inputs

def mod_kernel():
    """Reassemble mod 6.9 for 1.05e-0918 from the committed disassembly."""
    run([os.path.join(REPO, "scripts", "build-kernel.sh"), VER])
    data = open(os.path.join(REPO, "re", "kernel", VER, "disassembly", "game_trunc.gb"), "rb").read()
    if hashlib.md5(data).hexdigest() != MOD_MD5:
        raise SystemExit("the reassembled kernel is not mod 6.9 for 1.05e-0918")
    return data


# dv/src/<file>: (code origin, symbols pinned to kernel addresses)
C_BLOCKS = {
    "browser_icons.c":          (0x6b80, {"DrawString12": 0x7500, "wDrawColor": 0xd734, "RecolorIcon": 0x6d60}),
    "browser_scroll_repaint.c": (0x3d8c, {"browser_scroll_down": 0x3ed0, "FarCallDrawDetailBottom": 0x03dc, "DrawString": 0x08b7,
                                          "StoreDrawParams": 0x2791, "DrawNameWithIcon": 0x3ec8}),
    "ezjr_scroll.c":            (0x7962, {"ShiftRows": 0x7680}),
    "rom_menu.c":               (0x5a00, {"FarCallDrawString12": 0x05c0, "LastRomNameStub": 0x0368, "LastRomTickStub": 0x0370,
                                          "FarCallDrawLoadingBox": 0x0483, "ManageSaves": 0x6d11, "DrawRect": 0x27ba,
                                          "StoreDrawParams": 0x2791, "StarQueryStub": 0x3ee4, "StarToggleStub": 0x3eec,
                                          "ResortStub": 0x3ef4}),
    "settext.c":                (0x6400, {"FarCallDrawString12": 0x05c0, "hClip12": 0xfff9}),
    "flcfg.c":                  (0x6600, {"FarCallEzCfg": 0x5f00, "SetFpgaPage_B4": 0x466e, "DrawString": 0x08b7,
                                          "DrawRect": 0x27ba, "StoreDrawParams": 0x2791, "ReadJoypad": 0x3a4a,
                                          "SetText": 0x6400}),
    "auto_backup.c":            (0x7680, {"SmSaveOp": 0x6562, "RtcReadPage": 0x1a9a, "FarCallDrawString12": 0x05c0,
                                          "LastRomNameStub": 0x0368, "DrawRect": 0x27ba, "StoreDrawParams": 0x2791}),
}


def compile_block(src):
    """SDCC one dv/src file at its origin; returns (code, {global: address})."""
    origin, pins = C_BLOCKS[src]
    w = tempfile.mkdtemp(dir=BUILD)
    ihx, _ = compile_c(os.path.join(DV, "src", src), w, pins=[("_" + k, v) for k, v in pins.items()], code_origin=origin)
    mem = parse_ihx(ihx)
    lo, hi = min(mem), max(mem)
    if lo != origin:
        raise SystemExit(f"{src}: code starts at {lo:04x}, not {origin:04x}")
    syms = {}
    for name in os.listdir(w):
        if name.endswith(".noi"):
            for line in open(os.path.join(w, name)):
                p = line.split()
                if len(p) == 3 and p[0] == "DEF" and p[1].startswith("_") and not p[1].startswith("__"):
                    syms[p[1][1:]] = int(p[2], 16)
    return bytes(mem.get(a, 0xFF) for a in range(lo, hi + 1)), syms


def mapsyms(path):
    """label -> address from an rgblink map; __end_<section>__ and __end__ (end of the last section)."""
    import re
    syms, end = {}, 0
    for line in open(path):
        m = re.match(r"\s+\$([0-9a-f]{4}) = (\S+)", line, re.I)
        if m and "." not in m.group(2):
            syms[m.group(2)] = int(m.group(1), 16)
        m = re.match(r'\s+SECTION: \$([0-9a-f]{4})-\$([0-9a-f]{4}).*\["(\w+)"\]', line, re.I)
        if m:
            e = int(m.group(2), 16) + 1
            end = max(end, e)
            syms[f"__end_{m.group(3)}__"] = e
    syms["__end__"] = end
    return syms


def assemble(name, *defines):
    """rgbasm + rgblink dv/asm/<name>.asm into dv/build; returns (rom image, symbols)."""
    obj, rom, mp = (os.path.join(BUILD, name + ext) for ext in (".o", ".gb", ".map"))
    run(["rgbasm", "-I", BUILD, *[f"-D{d}" for d in defines], "-o", obj, os.path.join(ASM, name + ".asm")])
    run(["rgblink", "-p", "0xFF", "-m", mp, "-o", rom, obj])
    return open(rom, "rb").read(), mapsyms(mp)


# ---------------------------------------------------------------- patching

class Rom:
    def __init__(self, data):
        self.d = bytearray(data)
        self.log = []

    def patch(self, bank, addr, old, new, what):
        o = off(bank, addr)
        old, new = bytes.fromhex(old), bytes.fromhex(new)
        got = bytes(self.d[o:o + len(old)])
        if got != old:
            raise SystemExit(f"{what}: {bank:02x}:{addr:04x} is {got.hex(' ')}, expected {old.hex(' ')}")
        self.d[o:o + len(new)] = new
        self.log.append(f"{bank:02x}:{addr:04x}  {what}")

    def find_one(self, bank, lo, hi, pat, what):
        p = bytes.fromhex(pat)
        o0, o1 = off(bank, lo), off(bank, hi)
        hits = []
        i = self.d.find(p, o0, o1)
        while i != -1:
            hits.append(i)
            i = self.d.find(p, i + 1, o1)
        if len(hits) != 1:
            raise SystemExit(f"{what}: {len(hits)} matches in {bank:02x}:{lo:04x}-{hi:04x}")
        return (hits[0] - bank * 0x4000) + (0x4000 if bank else 0)


def font_tables(rom):
    """Tamzen 6x12 as a fixed-width font in the mod's Font12 format (scripts/font12-pack.py)."""
    font = bdf.load(os.path.join(DV, "fonts", "Tamzen6x12r.bdf"))
    bitmaps = bytearray()
    for code in range(0x20, 0x80):
        cell = icons.cell(0x7F) if code == 0x7F else bdf.cell(font, code, 12, 0)   # $7F: the star icon
        for row in cell:
            v = 0
            for c, px in enumerate(row[:10] if code == 0x7F else row[:6]):
                if px:
                    v |= 1 << (15 - c)
            bitmaps += bytes((v >> 8, v & 0xFF))
    for code in range(0xC0, 0xC5):                     # smaller icons, 1 px from the row's top and left
        for row in icons.cell(code):
            v = 0
            for c, px in enumerate(row):
                if px:
                    v |= 1 << (15 - c)
            bitmaps += bytes((v >> 8, v & 0xFF))
    assert len(bitmaps) == 101 * 24

    old_m = off(2, 0x6978)
    adv = bytes([6] * 95 + [12]) + bytes(rom.d[old_m + 96: old_m + 101])         # icons (and the $7F star) advance 12
    w = bytes([0] + [6] * 94 + [10]) + bytes(rom.d[old_m + 101 + 96: old_m + 101 + 101])
    lcol = bytes(101)                                  # class 0: never kerns
    rrow = bytes((505 & 0xFF, 505 >> 8)) * 101
    metrics = adv + w + lcol + rrow + b"\x00"
    assert len(metrics) == 506
    return bytes(bitmaps), metrics


def build(data):
    r = Rom(data)
    stub = lambda target, bank: bytes([0xcd, 0x8d, 0x07, target & 0xff, target >> 8, bank, 0x00])   # far call via 00:078d

    # --- palette: index 0 black, 1 green, 2 blue, 3 white (on a GBC's default colors) ---
    r.patch(0, 0x01b0, "3ee4e047e0483e1be049", "3e27e047e0483ee4e049", "BGP $27 (OBP0 same, OBP1 $E4)")

    # --- list selection bar: ink 0 / paper 3 -> ink 0 (black) / paper 1 (green) ---
    sel_old, sel_new = "210300e53e00f533cd9127", "210100e53e00f533cd9127"
    for bank, lo, hi, name in [(0, 0x0bd1, 0x0c10, "DrawDirEntryLabel"),
                               (1, 0x415d, 0x4175, "DrawBrowserEntries_hilite"),
                               (1, 0x4365, 0x4385, "DrawBrowserDetail_mode3Hilite"),
                               (1, 0x4459, 0x4475, "DrawBrowserDetail_afterFocusInk")]:
        a = r.find_one(bank, lo, hi, sel_old, name)
        r.patch(bank, a, sel_old, sel_new, f"selection bar: black on green ({name})")

    # --- tab strip (TabStrip12, 02:5e00): tabs and rule in green ---
    r.patch(2, 0x5e68, "210300e5aff533cd9127", "210100e5aff533cd9127", "PICK ROM banner black on green")
    r.patch(2, 0x5ec5, "210300e5aff533cd9127", "210100e5aff533cd9127", "active tab black on green")
    r.patch(2, 0x5ed7, "3e03f533cd9127", "3e01f533cd9127", "other tabs green")
    r.patch(2, 0x5f50, "2e03e53e03f533cd9127", "2e01e53e01f533cd9127", "rule green")

    # --- font: Tamzen 6x12, fixed width ---
    bm, metrics = font_tables(r)
    o = off(2, 0x6000); r.d[o:o + len(bm)] = bm; r.log.append("02:6000  Font12 bitmaps: Tamzen 6x12")
    o = off(2, 0x6978); r.d[o:o + len(metrics)] = metrics; r.log.append("02:6978  Font12Metrics: fixed 6 px, no kerning")

    # --- hide .gb/.gbc in 12px text (asm/ext_hide.asm: Fit12Vis at 02:43d0, Fit12Marq at 02:43ef) ---
    eh, sym = assemble("ext_hide")
    code = eh[off(2, 0x43d0):off(2, sym["__end__"])]
    assert (sym["Fit12Vis"], sym["Fit12Marq"]) == (0x43d0, 0x43ef)
    r.patch(2, 0x43d0, "ff" * len(code), code.hex(), "Fit12Vis / Fit12Marq: hide trailing .gb/.gbc")
    r.patch(2, 0x76f4, "cd0071", "cdd043", "DrawString12 lays out through Fit12Vis")
    r.patch(0, 0x0243, "cd8d0700710200", "cd8d07ef430200", "MarqueeWidth12 fit test through Fit12Marq")

    # --- 12px only: every read of hUiMode ($fffb) loads 1 instead ---
    n1 = n2 = 0
    for o in range(len(r.d) - 3):
        if r.d[o] == 0xF0 and r.d[o + 1] == 0xFB and r.d[o + 2] in (0xB7, 0x3C, 0xF8):   # ldh a,[$fffb]
            r.d[o:o + 2] = b"\x3e\x01"; n1 += 1                                      # ld a,1
        elif r.d[o:o + 4] == b"\xfa\xfb\xff\xb7":                                     # ld a,[$fffb]; or a
            r.d[o:o + 3] = b"\x3e\x01\x00"; n2 += 1                                  # ld a,1; nop
    if (n1, n2) != (21, 41):
        raise SystemExit(f"hUiMode reads: found {n1} + {n2}, expected 21 + 41")
    r.log.append(f"--:----  12px only: {n1} + {n2} hUiMode reads load 1")

    # --- banks 5 and 8 (asm/bank5.asm, asm/bank8.asm), assembled up front: bank 8 calls ScoreKeys ---
    scroll, scroll_syms = compile_block("ezjr_scroll.c")
    open(os.path.join(BUILD, "ezjr_scroll_7962.bin"), "wb").write(scroll)
    open(os.path.join(BUILD, "rank_table.bin"), "wb").write(rank_table.table_bytes(rank_table.load(os.path.join(DV, "ranking.txt"))))
    b5, sym5 = assemble("bank5")
    b8, sym8 = assemble("bank8", f"SCOREKEYS=${sym5['ScoreKeys']:04X}")

    # --- bank 8: Pokemon-style status box, HELP credit line ---
    def b8code(addr, end): return b8[off(8, addr):off(8, end)]
    msg = b8code(0x7e80, sym8["__end_msgbox__"])
    assert len(msg) <= 0xe7
    r.patch(8, 0x7f06, "ff" * (0x7e80 + len(msg) - 0x7f06), "ff" * (0x7e80 + len(msg) - 0x7f06), "MsgBox12 room after the old block is free")
    o = off(8, 0x7e80); r.d[o:o + 0x86] = b"\xff" * 0x86; r.d[o:o + len(msg)] = msg
    r.log.append("08:7e80  MsgBox12: black box, white Pokemon-style frame, white text")
    old_line = "e8ebf8143600f8147ef819963022f8145e16002100003919"  # first bytes of Help12's line()
    hl = b8code(0x7db1, sym8["__end_helpline__"])
    assert len(hl) <= 0x52
    r.patch(8, 0x7db1, old_line, old_line, "Help12 line() is the stock-mod one")
    o = off(8, 0x7db1); r.d[o:o + 0x52] = hl + b"\xff" * (0x52 - len(hl))
    r.log.append("08:7db1  HelpLine: 26-byte buffer")
    credit = b8code(0x7bd2, sym8["__end_credit__"])
    r.patch(8, 0x7bd2, "ff" * len(credit), credit.hex(), "HelpCredit string")
    r.patch(8, 0x7d96, "211354e511097b", "211754e511097b", "HELP: github.com/lukesau/ezgb on one line")
    r.patch(8, 0x7da3, "210460e5111c7b", f"21{len(credit) - 1:02x}60e511d27b", "HELP: credit line under it")

    # --- row icons in blue on normal rows (browser_icons.c at 02:6b80, in the room Tamzen's
    #     metrics left over), the far stub at 00:3ec8 pointed there ---
    code, _ = compile_block("browser_icons.c")
    assert 0x6978 + len(metrics) <= 0x6b80 and 0x6b80 + len(code) <= 0x6d60
    o = off(2, 0x6b80); r.d[o:o + len(code)] = code
    r.log.append(f"02:6b80  DrawNameWithIcon: one pass + RecolorIcon ({len(code)} bytes)")
    r.patch(0, 0x3ec8, "cd8d07807e0200c9", "cd8d07806b0200c9", "row-draw stub -> 02:6b80")

    # --- wrap-around, n/total counter, SORT TOP + play counts, stars ---
    lo5, hi5 = 0x7962, sym5["__end__"]
    o = off(5, lo5)
    if any(x != 0xFF for x in r.d[o:off(5, hi5)]):
        raise SystemExit("bank 5 target is not free")
    r.d[o:off(5, hi5)] = b5[o:off(5, hi5)]
    r.log.append(f"05:{lo5:04x}  bank 5 block: scroll, counter, TOP sort, play counts, stars ({hi5 - lo5} bytes)")
    lo, hi = sym5["ShiftRows"], sym5["__end_vrammove__"]
    assert lo == 0x7680 and hi <= 0x7700
    o = off(5, lo)
    if any(x != 0xFF for x in r.d[o:off(5, hi)]):
        raise SystemExit("bank 5 ShiftRows target is not free")
    r.d[o:off(5, hi)] = b5[o:off(5, hi)]
    r.log.append(f"05:{lo:04x}  ShiftRows: a one-row scroll moves the drawn rows in VRAM ({hi - lo} bytes)")
    r.patch(0, 0x3ed0, r.d[off(0, 0x3ed0):off(0, 0x3ed8)].hex(), (stub(scroll_syms["ezjr_scroll_down"], 5) + b"\xc9").hex(), "DOWN -> 05 ezjr_scroll_down (wraps)")
    r.patch(0, 0x3fbb, r.d[off(0, 0x3fbb):off(0, 0x3fc3)].hex(), (stub(scroll_syms["ezjr_scroll_up"], 5) + b"\xc9").hex(), "UP (hook 00:02f0 calls 3fbb) -> 05 ezjr_scroll_up (wraps)")
    # the down hook's repaint: only a one-line shift is painted bottom-up, a wrap gets the full repaint
    rp, _ = compile_block("browser_scroll_repaint.c")
    assert len(rp) <= 0x127
    o = off(0, 0x3d8c); r.d[o:o + 0x127] = rp + b"\xff" * (0x127 - len(rp))
    r.log.append(f"00:3d8c  BrowserScrollDownRepaint: skip wraps ({len(rp)} bytes)")
    # one-pass rows: the icon is recolored in VRAM afterwards (asm/bank2_recolor.asm)
    b2, sym2 = assemble("bank2_recolor")
    rc = b2[off(2, 0x6d60):off(2, sym2["__end__"])]
    o = off(2, 0x6d60); r.d[o:o + len(rc)] = rc
    r.log.append("02:6d60  RecolorIcon: blue icons without a second pass")
    r.patch(0, 0x0380, "3e01b7cab708f805367cc3c005", (stub(sym5["TabNumFar"], 5) + b"\xc9").hex() + "ffffffffff", "entry number -> 05 TabNumFar (n/total, green)")
    # bank 0 stubs in the old scroll code's room (00:3ed8.., unreachable now)
    hook = stub(sym5["PlayCount"], 5) + bytes.fromhex("c31076")                                  # then jp LastRomSaveHook
    starq = stub(sym5["StarQuery"], 5) + b"\xc9"
    star = stub(sym5["StarToggle"], 5) + b"\xc9"
    resort = bytes.fromhex("cd8d076b740800") + stub(sym5["MarkStars"], 5) + b"\xc9"                 # sort, then mark stars
    blob = hook + b"\xff" * (12 - len(hook)) + starq + star + resort
    o = off(0, 0x3ed8); r.d[o:o + len(blob)] = blob
    assert (0x3ed8 + 12, 0x3ed8 + 20, 0x3ed8 + 28) == (0x3ee4, 0x3eec, 0x3ef4)
    r.log.append("00:3ed8  stubs: PlayCountHook, StarQueryStub 3ee4, StarToggleStub 3eec, ResortStub 3ef4")
    r.patch(1, 0x48c1, "c31076", "c3d83e", "launch tail -> PlayCountHook (count a play)")
    r.patch(0, 0x0490, "cdd403", "cdf43e", "fastlaunch_boot's sort -> ResortStub (sort, mark stars)")
    # bank 8: BuildKeysTop after the HELP credit, and the sort's build_keys call pointed at it
    bk = sym8["BuildKeysTop"]
    code8 = b8code(bk, sym8["__end_buildkeys__"])
    o = off(8, bk)
    if any(x != 0xFF for x in r.d[o:o + len(code8)]):
        raise SystemExit("bank 8 BuildKeysTop target is not free")
    r.d[o:o + len(code8)] = code8
    r.log.append(f"08:{bk:04x}  BuildKeysTop: build_keys, then 05 ScoreKeys ({len(code8)} bytes)")
    r.patch(8, 0x7496, "cd8b77", f"cd{bk & 0xff:02x}{bk >> 8:02x}", "sort: build_keys -> BuildKeysTop")
    # hold-A menu with Star (rom_menu.c, 12px only, same slot)
    rm, _ = compile_block("rom_menu.c")
    assert len(rm) <= 0x4cb
    o = off(4, 0x5a00); r.d[o:o + 0x4cb] = rm + b"\xff" * (0x4cb - len(rm))
    r.log.append(f"04:5a00  RomMenu: Start / Manage saves / Star ({len(rm)} bytes)")
    # SET tab (flcfg.c and settext.c copies, in their own slots): AUTO SAVE, DAILY BACKUP, SORT A-Z
    # (the SGB BOOT row, its record at page $11 $B100), FAST LAUNCH, PICK ROM; no UI row; a 2 px margin
    for src, end in (("settext.c", 0x6562), ("flcfg.c", 0x6d11)):
        code, syms = compile_block(src)
        origin = C_BLOCKS[src][0]
        if origin + len(code) > end:
            raise SystemExit(f"{src}: {len(code)} bytes, its slot holds {end - origin}")
        o = off(4, origin); r.d[o:off(4, end)] = code + b"\xff" * (end - origin - len(code))
        r.log.append(f"04:{origin:04x}  {src}: SET tab rows reordered, DAILY BACKUP, left margin ({len(code)} of {end - origin} bytes)")

    # --- one backup per game of the save from before the day's first session (auto_backup.c at 04:7680) ---
    ab, ab_syms = compile_block("auto_backup.c")
    assert ab_syms["AutoBackup"] == 0x7680 and 0x7680 + len(ab) <= 0x7c00
    o = off(4, 0x7680)
    if any(x != 0xFF for x in r.d[o:o + len(ab)]):
        raise SystemExit("bank 4 AutoBackup target is not free")
    r.d[o:o + len(ab)] = ab
    r.log.append(f"04:7680  AutoBackup: back the save up on the day's first dump, one kept ({len(ab)} bytes)")
    abstub = b"\xc5" + stub(0x7680, 4) + bytes.fromhex("3e00f533c3210f")    # push bc; AutoBackup; then the hook's own tail
    r.patch(0, 0x3e8d, "ff" * len(abstub), abstub.hex(), "AutoBackupStub")
    r.patch(0, 0x03bf, "c53e00f533c3210f", "c38d3effffffffff", "SaveStampHook: after the stamp check -> AutoBackupStub")

    # --- FW5 fast load only on the Chromatic (asm/detect.asm) ---
    dt, symd = assemble("detect")
    code = dt[:symd["__end__"]]
    r.patch(1, 0x7ec6, "ff" * len(code), code.hex(), "Detect: FW5 fast load only on the Chromatic")
    r.patch(1, 0x480b, "21007f", "cdc67e", "SetFpga7FD4 calls Detect")

    # --- highlights and accents in green everywhere (after all code is in) ---
    n03 = n33 = 0
    for old, new_ in [("210300e53e00f533cd9127", "210100e53e00f533cd9127"), ("210300e5aff533cd9127", "210100e5aff533cd9127")]:
        ob, nb = bytes.fromhex(old), bytes.fromhex(new_)
        i = r.d.find(ob)
        while i != -1:
            r.d[i:i + len(ob)] = nb; n03 += 1; i = r.d.find(ob, i + 1)
    for old, new_ in [("210300e53e03f533cd9127", "210100e53e01f533cd9127"), ("2e03e53e03f533cd9127", "2e01e53e01f533cd9127")]:
        ob, nb = bytes.fromhex(old), bytes.fromhex(new_)
        i = r.d.find(ob)
        while i != -1:
            r.d[i:i + len(ob)] = nb; n33 += 1; i = r.d.find(ob, i + 1)
    r.log.append(f"--:----  green highlights: {n03} black-on-white -> black-on-green, {n33} solid white -> solid green")
    return bytes(r.d), r.log


# ---------------------------------------------------------------- IPS

def ips_make(src, dst):
    """One IPS record per run of changed bytes (files of the same size)."""
    assert len(src) == len(dst) <= 0xFFFFFF
    out = bytearray(b"PATCH")
    i = 0
    while i < len(dst):
        if src[i] == dst[i]:
            i += 1
            continue
        if i == 0x454F46:                     # an offset spelling "EOF" would end the patch: start a byte early
            i -= 1
        j = i + 1
        while j < len(dst) and j - i < 0xFFFF and src[j] != dst[j]:
            j += 1
        out += i.to_bytes(3, "big") + (j - i).to_bytes(2, "big") + dst[i:j]
        i = j
    return bytes(out + b"EOF")


def ips_apply(data, patch):
    d = bytearray(data)
    if patch[:5] != b"PATCH":
        raise ValueError("not an IPS patch")
    i = 5
    while patch[i:i + 3] != b"EOF":
        o = int.from_bytes(patch[i:i + 3], "big")
        n = int.from_bytes(patch[i + 3:i + 5], "big")
        i += 5
        if n == 0:                            # RLE record
            n = int.from_bytes(patch[i:i + 2], "big")
            d[o:o + n] = patch[i + 2:i + 3] * n
            i += 3
        else:
            d[o:o + n] = patch[i:i + n]
            i += n
    return bytes(d)


def main():
    ap = argparse.ArgumentParser(description="Build ezgb-dv (the EZ-Flash Junior menu) from this repo.")
    ap.add_argument("--stock", help="EZ-Flash's ezgb.dat 1.05e-0918: also write the IPS patch for it and check it")
    ap.add_argument("-o", "--out", default=os.path.join(BUILD, "ezgb-dv.dat"))
    args = ap.parse_args()
    os.makedirs(BUILD, exist_ok=True)

    dat, log = build(mod_kernel())
    print("\n".join(log))
    open(args.out, "wb").write(dat)
    md5 = hashlib.md5(dat).hexdigest()
    print(f"wrote {args.out}  md5 {md5}")

    if args.stock:
        stock = open(args.stock, "rb").read()
        if hashlib.md5(stock).hexdigest() != STOCK_MD5:
            raise SystemExit(f"{args.stock} is not EZ-Flash's ezgb.dat 1.05e-0918 (md5 {STOCK_MD5})")
        if len(stock) != len(dat):
            raise SystemExit(f"size differs: stock {len(stock)}, ezgb-dv {len(dat)}")
        ips = ips_make(stock, dat)
        if ips_apply(stock, ips) != dat:
            raise SystemExit("IPS round trip failed")
        path = os.path.join(BUILD, "ezgb-dv-1.05e-0918.ips")
        open(path, "wb").write(ips)
        print(f"wrote {path} ({len(ips)} bytes): ezgb.dat {STOCK_MD5} -> ezgb-dv {md5}")


if __name__ == "__main__":
    main()
