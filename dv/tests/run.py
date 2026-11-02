#!/usr/bin/env python3
"""Run the ezgb-dv emulator tests: each dv/tests/test_*.asm links the real
dv/asm (or dv/src) code into a small test ROM, PyBoy runs it headless, and the
results it leaves in WRAM are checked here.

    pip install pyboy
    python3 dv/tests/run.py
"""
import os
import sys
import tempfile

TESTS = os.path.dirname(os.path.abspath(__file__))
DV = os.path.dirname(TESTS)
OUT = os.path.join(DV, "build", "tests")
sys.path.insert(0, DV)
import build                                   # noqa: E402  (dv/build.py: kernel, compiler, paths)
import rank_table                              # noqa: E402
from sdcc_build import compile_c, parse_ihx    # noqa: E402

try:
    from pyboy import PyBoy
except ImportError:
    raise SystemExit("the tests need PyBoy: pip install pyboy")


def rom(name, *fix):
    """Assemble dv/tests/<name>.asm into a test ROM."""
    o, gb = os.path.join(OUT, name + ".o"), os.path.join(OUT, name + ".gb")
    build.run(["rgbasm", "-I", OUT, "-I", build.ASM, "-I", os.path.join(TESTS, "fixtures"), "-o", o, os.path.join(TESTS, name + ".asm")])
    build.run(["rgblink", "-o", gb, o])
    build.run(["rgbfix", "-v", *fix, "-p", "0xFF", gb])
    return gb


def emulate(gb):
    pb = PyBoy(gb, window="null", sound_emulated=False)
    for _ in range(400):                       # the emulator runs a boot ROM first (~2.5 s)
        pb.tick()
    m = pb.memory
    wram, vram, nest = bytes(m[0xC000:0xC200]), bytes(m[0x8000:0x9800]), m[0xD6D0]   # results, VRAM, DiNest depth
    pb.stop(save=False)
    return wram, vram, nest


def fixture(name):
    return open(os.path.join(TESTS, "fixtures", name), "rb").read()


def prepare():
    os.makedirs(OUT, exist_ok=True)
    kernel = build.mod_kernel()
    open(os.path.join(OUT, "gfxrowtable.bin"), "wb").write(kernel[0x2fbb:0x2fbb + 288])
    open(os.path.join(OUT, "hilite_vram.bin"), "wb").write(hilite_pattern(kernel[0x2fbb:0x2fbb + 288]))
    tab = kernel[0x2fbb:0x2fbb + 288]
    with open(os.path.join(OUT, "hilite_bar.inc"), "w") as f:
        f.write("".join(f"DEF BAR_COL{c} EQU ${0x8000 + hilite_addrs(tab, 80)[c]:04X}\n" for c in (3, 7)))
    open(os.path.join(OUT, "rank_table.bin"), "wb").write(rank_table.table_bytes(rank_table.load(os.path.join(DV, "ranking.txt"))))
    # ShiftRows is bank5.asm's at $7680 in the real build, test_scroll.asm's recorder at $0F00 in the test ROM;
    # MoveHighlightStub is the far stub at 00:3e9c, test_scroll.asm's recorder at $0F40
    for origin, name, shift, move in ((0x7962, "ezjr_scroll_7962.bin", 0x7680, 0x3E9C), (0x1000, "scroll_test_1000.bin", 0x0F00, 0x0F40)):
        w = tempfile.mkdtemp(dir=OUT)
        ihx, _ = compile_c(os.path.join(DV, "src", "ezjr_scroll.c"), w, pins=[("_ShiftRows", shift), ("_MoveHighlightStub", move)],
                           code_origin=origin)
        mem = parse_ihx(ihx)
        open(os.path.join(OUT, name), "wb").write(bytes(mem.get(a, 0xFF) for a in range(min(mem), max(mem) + 1)))
        if origin == 0x1000:
            syms = {}
            for line in open(os.path.join(w, "out.noi")):
                f = line.split()
                if len(f) == 3 and f[0] == "DEF":
                    syms[f[1]] = int(f[2], 16)
            with open(os.path.join(OUT, "scroll_syms.inc"), "w") as f:
                f.write(f"DEF Down EQU ${syms['_ezjr_scroll_down']:04X}\nDEF Up EQU ${syms['_ezjr_scroll_up']:04X}\n")


def expect_top():
    """SORT TOP keys the test records should get with the current ranking.txt."""
    rank = {n: b for n, h, b in rank_table.load(os.path.join(DV, "ranking.txt"))}
    games = [("Pokemon Crystal.gbc", 1), ("Aladdin.gbc", 1), ("Tetris DX.gbc", 1), ("Unknown Game.gb", 1), ("Folder", 0), ("Mario Golf.gbc", 1)]
    plays = {"Aladdin.gbc": (3, 0x80), "Tetris DX.gbc": (5, 0x81), "Mario Golf.gbc": (25, 0x80)}   # matches fixtures/t_table.bin
    keys = fixture("t_keys.bin")

    def score(n):
        if n in plays and plays[n][1] & 1:
            return 255                         # starred
        c = plays.get(n, (0, 0))[0]
        return min(254, rank.get(n, 0) + 12 * c)

    exp = bytearray()
    for i, (n, is_file) in enumerate(games):
        k = bytearray(keys[16 * i:16 * i + 16])
        if is_file:
            k[2:14] = k[1:13]
            k[1] = ~score(n) & 0xFF
        exp += k
    return bytes(exp)


# ---------------------------------------------------------------- tests: yield (ok, label)

def t_ext():
    m, _, _ = emulate(rom("test_ext", "-m", "0x01"))
    names = ["Donkey Kong.gb", "Donkey Kong.gb", "Pokemon Puzzle Challenge.gbc", "Pokemon Puzzle Challenge.gbc",
             "Super Mario Land 2 - 6 Golden Coins.gb", "Super Mario Land 2 - 6 Golden Coins.gb", "README.TXT", "README.TXT",
             "<icon>Aladdin.gbc", ".gb", "Game.GBC", "Aladdin.gbc (len 5)", "x.gbcx", "Tetris.gbx", "Tetris.gbx"]
    which = ["vis", "marq", "vis", "marq", "vis", "marq", "vis", "marq", "vis", "vis", "vis", "vis", "vis", "vis", "marq"]
    want = [(11, 11), (11, 14), (24, 24), (24, 28), (35, 24), (35, 24), (0, 10), (0, 10), (8, 8), (0, 3), (4, 4), (5, 5), (0, 6), (0, 10), (0, 10)]
    for k, (n, w, e) in enumerate(zip(names, which, want)):
        got = (m[2 * k], m[2 * k + 1])
        yield got == e, f"hide .gb/.gbc: {w:4} {n:40} len {got[0]:2}, fit {got[1]:2} (want {e})"


def t_scroll():
    m, _, _ = emulate(rom("test_scroll"))
    # per case (test_scroll.asm): (dirty, base, sel), the ShiftRows call (dst_y, src_y, batches, step) or None,
    # the MoveHighlight call's row or None, the marquee index after, and the repeat timer after.
    # A one-row scroll moves list rows 1..8 (y 32..127) and leaves a two-row repaint; a move in the
    # window goes to MoveHighlight, which here does what it does to the state (dirty 0) or declines,
    # leaving the stock repaint; a wrap on a longer list redraws the page. Every move puts the marquee
    # index back to $EEEE; a held key moves after 18 frames, then every 6.
    C, K = 0xEEEE, 0x1234
    # (dirty, base, sel), shift, recolor row, marquee index, repeat timer, repeat count
    want = [((0, 0, 1), None, 1, C, 50, 0), ((2, 0, 1), None, 1, C, 50, 0),
            ((2, 1, 9), (20, 32, 24, 4), None, C, 50, 0), ((1, 0, 0), None, None, C, 50, 0),
            ((1, 29, 9), None, None, C, 50, 0), ((3, 4, 0), (136, 124, 24, 0xFC), None, C, 50, 0),
            ((0, 5, 2), None, 2, C, 50, 0), ((3, 5, 2), None, 2, C, 50, 0),
            ((0, 0, 0), None, 0, C, 50, 0), ((1, 0, 0), None, 0, C, 50, 0), ((0, 0, 3), None, 3, C, 50, 0),
            ((0, 0, 2), None, None, K, 50, 0), ((0, 0, 3), None, 3, C, 56, 1),
            ((0, 0, 1), None, 1, C, 0, 1), ((0, 0, 1), None, 1, C, 60, 0),
            ((0, 0, 3), None, 3, C, 56, 2), ((0, 0, 3), None, 3, C, 55, 3),
            ((0, 0, 3), None, 3, C, 54, 6), ((0, 0, 3), None, 3, C, 53, 6)]
    names = ["down from top", "down, declined", "down on row 9", "down on last -> wrap", "up on first -> last",
             "up row 0 mid", "up mid page", "up, declined", "short: down on last", "short: down, declined",
             "short: up on first", "held 17 frames", "held 18 frames", "held 18, hFrame wraps", "other key down",
             "2nd repeat: 6 frames", "3rd repeat: 5", "6th repeat: 4", "7th on: 3"]
    for k, (n, w) in enumerate(zip(names, want)):
        r = m[16 * k:16 * k + 16]
        g = ((r[0], r[1] | r[2] << 8, r[3]), tuple(r[4:8]) if r[7] or r[6] else None, r[9] if r[8] else None,
             r[10] | r[11] << 8, r[12], r[13])
        yield g == w, (f"scroll: {n:22} dirty={g[0][0]} base={g[0][1]} sel={g[0][2]} shift={g[1]} recolor={g[2]} "
                       f"marquee=${g[3]:04X} timer={g[4]} rep={g[5]}" + ("" if g == w else f" (want {w})"))


def t_counter():
    m, _, _ = emulate(rom("test_counter", "-m", "0x01"))
    for k, w in enumerate(["   2/39", "  39/39", "    1/5", "100/416", "    0/0", "  39/39", "416/416"]):
        raw = m[8 * k:8 * k + 8]
        s = raw[:7].decode("ascii", "replace")
        yield s == w and raw[7] == 0, f"counter: {s!r} (want {w!r})"


def t_top():
    m, _, _ = emulate(rom("test_top", "-m", "0x1B", "-r", "0x04"))
    yield m[0x00:0x60] == expect_top(), "SORT TOP keys: ranking + play counts + star"
    yield m[0x60:0xC0] == fixture("t_expect_az.bin"), "SORT A-Z keys: starred first, rest A-Z"


def t_star():
    m, _, _ = emulate(rom("test_star", "-m", "0x1B", "-r", "0x04"))
    yield m[8 + 18 + 16 + 32] == 0xAA, "star test ran to the end"
    for label, g, w in zip(["query unstarred", "toggle -> starred", "query -> starred", "toggle -> unstarred", "toggle new game -> starred"],
                           m[0:5], [0, 1, 1, 0, 1]):
        yield g == w, f"star: {label:26} {g} (want {w})"
    names = ["Pokemon Crystal", "Aladdin", "Tetris DX (starred)", "Unknown Game", "Folder (dir)", "Mario Golf"]
    for i, n in enumerate(names):
        mark, guard, attr = m[8 + 3 * i], m[8 + 3 * i + 1], m[8 + 3 * i + 2]
        want = 0x5A if i == 2 else 0
        yield mark == want and guard == 0 and attr == (0x10 if i == 4 else 0x20), f"MarkStars: {n:20} byte 252 = {mark:02x} (want {want:02x})"
    nm = m[0x1A:0x2A].split(b"\0")[0]
    yield nm == b"Tetris DX.gbc", f"MarkStars leaves names intact: {nm}"
    play = m[0x2A:0x4A]

    def entry(h):
        for k in range(8):
            if (play[4 * k] | play[4 * k + 1] << 8) == h and play[4 * k + 3] & 0x80:
                return play[4 * k + 2], play[4 * k + 3]
    for n, w in [("Aladdin.gbc", (3, 0x80)), ("Brand New.gb", (0, 0x81)), ("Tetris DX.gbc", (5, 0x81))]:
        g = entry(rank_table.name_hash(n))
        yield g == w, f"play table: {n:16} {g} (want {w})"


def t_init():
    m, _, _ = emulate(rom("test_init", "-m", "0x1B", "-r", "0x04"))
    yield (m[0] | m[1] << 8, m[2], m[3]) == (rank_table.name_hash("Pokemon Crystal.gbc"), 2, 0x80), "first use: play table cleared, then counted"
    yield m[260:264] == b"EZJR", "first use: EZJR signature written"


ICON_MASK = [0x00, 0x7F] + [0xFF] * 18     # plane 0 of a plain row: RecolorIcon's blue icon at x 0..8


def hilite_addrs(tab, py):
    """VRAM offsets (from $8000) of pixel row py's plane-0 byte in each of the 20 tile columns."""
    return [(tab[2 * py] | tab[2 * py + 1] << 8) - 0x8000 + 16 * c for c in range(20)]


def hilite_pattern(tab):
    """Random VRAM, except list row 3 (y 56..67), shaped like a plain row."""
    import random
    rng = random.Random(12)
    v = bytearray(rng.randrange(256) for _ in range(0x1800))
    for py in range(56, 68):
        for c, a in enumerate(hilite_addrs(tab, py)):
            g = rng.randrange(256)
            v[a], v[a + 1] = g & ICON_MASK[c], g
    return bytes(v)


def t_hilite():
    m, vram, _ = emulate(rom("test_hilite", "-m", "0x01"))
    tab = open(os.path.join(OUT, "gfxrowtable.bin"), "rb").read()
    want = bytearray(open(os.path.join(OUT, "hilite_vram.bin"), "rb").read())
    for py in range(32, 44):                          # plain -> bar: plane 0 = ~(p0 | p1), plane 1 = 0
        for a in hilite_addrs(tab, py):
            want[a], want[a + 1] = ~(want[a] | want[a + 1]) & 0xFF, 0
    for py in range(44, 56):                          # bar -> plain: g = ~p0; plane 0 = g minus the icon, plane 1 = g
        for c, a in enumerate(hilite_addrs(tab, py)):
            g = ~want[a] & 0xFF
            want[a], want[a + 1] = g & ICON_MASK[c], g
    src = [0x00, 0xFF, 0x81, 0x7E, 0x3C, 0xC3, 0x18, 0xE7, 0x01, 0x80, 0x55, 0xAA]     # Src12
    for c, xm in ((3, 0x00), (7, 0xFF)):              # BlitCol1Hook, hBarBlit set: plane 0 = bits ^ xm ^ $FF, plane 1 = 0
        for r, py in enumerate(range(80, 92)):
            a = hilite_addrs(tab, py)[c]
            want[a], want[a + 1] = src[r] ^ xm ^ 0xFF, 0
    rows = lambda lo, hi: [b for py in range(lo, hi) for a in hilite_addrs(tab, py) for b in (a, a + 1)]
    yield m[0] == 0xAA and all(vram[a] == want[a] for a in rows(32, 44)), "HighlightRow: 12 rows x 20 columns, plane 0 = ~(p0 | p1), plane 1 = 0"
    yield all(vram[a] == want[a] for a in rows(44, 56)), "UnhighlightRow: plane 0 = ~p0 minus the icon (x 0..8), plane 1 = ~p0"
    yield all(vram[a] == want[a] for a in rows(56, 68)), "HighlightRow then UnhighlightRow: a plain row comes back byte for byte"
    bar = [b for py in range(80, 92) for c in (3, 7) for b in (hilite_addrs(tab, py)[c], hilite_addrs(tab, py)[c] + 1)]
    yield all(vram[a] == want[a] for a in bar), "BlitCol1Hook, hBarBlit set: 12 rows across a tile edge, plane 0 = bits ^ xm ^ $FF, plane 1 = 0"
    rc, rhl, rsp = m[0x10], m[0x11] | m[0x12] << 8, m[0x13] | m[0x14] << 8
    yield (rc, rhl) == (0x5A, rsp + 7), f"BlitCol1Hook, hBarBlit clear: on to blit_col1 with c = xm, hl = sp + 7 (c ${rc:02X}, hl - sp {rhl - rsp})"
    yield all(vram[a] == want[a] for a in range(0x1800)), "HighlightRow / UnhighlightRow / BlitCol1Hook: nothing else in VRAM changed"
    for k, n in enumerate((0, 7, 39, 416, 1000, 9999)):
        got = bytes(m[0x20 + 5 * k:0x25 + 5 * k])
        yield got == f"{n:04d}".encode() + b"\0", f"Digits4({n}): {got!r}"
    for k, n in enumerate((39, 416)):
        got = bytes(m[0x40 + 5 * k:0x45 + 5 * k])
        yield got == f"{n:04d}".encode() + b"\0", f"CounterDigits({n}) in the far stub's frame: {got!r}"


def t_recolor():
    m, vram, nest = emulate(rom("test_recolor", "-m", "0x01"))
    tab = open(os.path.join(OUT, "gfxrowtable.bin"), "rb").read()
    touched, good = set(), True
    for py in range(32, 44):
        a = (tab[2 * py] | tab[2 * py + 1] << 8) - 0x8000
        touched |= {a, a + 16}
        good &= (vram[a], vram[a + 1], vram[a + 16], vram[a + 17]) == (0x00, 0xFF, 0x7F, 0xFF)
    yield m[0] == 0xAA and good, "RecolorIcon: 12 rows, plane 0 cleared at x 0..8, plane 1 untouched"
    yield all(vram[a] == 0xFF for a in range(len(vram)) if a not in touched), "RecolorIcon: nothing else in VRAM changed"
    yield nest == 0, "RecolorIcon: interrupt nesting back to 0"


def main():
    prepare()
    passed = failed = 0
    for t in (t_ext, t_scroll, t_counter, t_top, t_star, t_init, t_recolor, t_hilite):
        for ok, label in t():
            print(("ok  " if ok else "FAIL"), label)
            passed += ok
            failed += not ok
    print(f"\n{passed} passed, {failed} failed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
