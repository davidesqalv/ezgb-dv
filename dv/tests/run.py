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
    open(os.path.join(OUT, "rank_table.bin"), "wb").write(rank_table.table_bytes(rank_table.load(os.path.join(DV, "ranking.txt"))))
    for origin, name in ((0x7962, "ezjr_scroll_7962.bin"), (0x1000, "scroll_test_1000.bin")):
        w = tempfile.mkdtemp(dir=OUT)
        ihx, _ = compile_c(os.path.join(DV, "src", "ezjr_scroll.c"), w, pins=[], code_origin=origin)
        mem = parse_ihx(ihx)
        open(os.path.join(OUT, name), "wb").write(bytes(mem.get(a, 0xFF) for a in range(min(mem), max(mem) + 1)))
        if origin == 0x1000:
            noi = open(os.path.join(w, "out.noi")).read()
            assert "_ezjr_scroll_up 0x10A6" in noi, "test_scroll.asm expects ezjr_scroll_up at $10A6"


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
    want = [(2, 0, 1), (1, 1, 9), (1, 0, 0), (1, 29, 9), (1, 4, 0), (3, 5, 2), (1, 0, 0), (1, 0, 3)]
    names = ["down from top", "down on row 9", "down on last -> wrap", "up on first -> last", "up row 0 mid",
             "up mid page", "short: down on last", "short: up on first"]
    for k, (n, w) in enumerate(zip(names, want)):
        g = (m[4 * k], m[4 * k + 1] | m[4 * k + 2] << 8, m[4 * k + 3])
        yield g == w, f"scroll: {n:22} dirty={g[0]} base={g[1]} sel={g[2]} (want {w})"


def t_counter():
    m, _, _ = emulate(rom("test_counter", "-m", "0x01"))
    for k, w in enumerate(["   2/39", "  39/39", "    1/5", "100/416", "    0/0"]):
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
    for t in (t_ext, t_scroll, t_counter, t_top, t_star, t_init, t_recolor):
        for ok, label in t():
            print(("ok  " if ok else "FAIL"), label)
            passed += ok
            failed += not ok
    print(f"\n{passed} passed, {failed} failed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
