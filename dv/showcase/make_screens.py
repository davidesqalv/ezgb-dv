#!/usr/bin/env python3
"""Screenshots for the README: ezgb-dv booted in SameBoy's core with a Game
Boy Color's colors, from a test SD card, with scripted buttons.

    scripts/setup-sameboy.sh && make -C tools/SameBoy CONF=debug sdl   # once
    brew install mtools && pip install pillow
    python3 dv/showcase/make_screens.py            # -> dv/docs/*.png
    python3 dv/showcase/make_screens.py --explore  # frames every 20 during boot

The card holds an empty file per game in dv/ranking.txt: the menu lists file
names only, so no ROMs are needed.
"""
import argparse
import glob
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DV = os.path.dirname(HERE)
REPO = os.path.dirname(DV)
SAMEBOY = os.path.join(REPO, "tools", "SameBoy")
OUT = os.path.join(DV, "build", "showcase")
DOCS = os.path.join(DV, "docs")
sys.path.insert(0, DV)
import build                                    # noqa: E402

from PIL import Image                           # noqa: E402

SCALE = 4


def sh(cmd, env=None):
    r = subprocess.run(cmd, capture_output=True, text=True, env=env)
    if r.returncode:
        raise SystemExit(f"{' '.join(cmd)} failed:\n{r.stdout}{r.stderr}")
    return r.stdout


def shot_tool():
    boot = os.path.join(SAMEBOY, "build", "bin", "SDL", "dmg_boot.bin")
    objs = glob.glob(os.path.join(SAMEBOY, "build", "obj", "Core", "*.o"))
    if not os.path.exists(boot) or not objs:
        raise SystemExit("SameBoy isn't built: scripts/setup-sameboy.sh, then make -C tools/SameBoy CONF=debug sdl")
    exe = os.path.join(OUT, "shot")
    sh(["cc", "-O2", "-I", SAMEBOY, "-o", exe, os.path.join(HERE, "shot.c"), *objs, "-lm"])
    return exe, boot


def make_card(path, cfg=None):
    """64 MiB FAT32 card: an empty file per ranked game."""
    names = [l.strip() for l in open(os.path.join(DV, "ranking.txt")) if l.strip() and not l.startswith("#")]
    src = os.path.join(OUT, "games")
    shutil.rmtree(src, ignore_errors=True)
    os.makedirs(src)
    with open(path, "wb") as f:
        f.truncate(64 << 20)
    env = dict(os.environ, MTOOLS_SKIP_CHECK="1")
    sh(["mformat", "-i", path, "-F", "-v", "EZJR", "::"], env)
    for n in sorted(names, key=str.lower):     # A-Z on the card, like a freshly copied folder
        p = os.path.join(src, n)
        with open(p, "wb") as f:
            f.truncate(32 << 10)
        sh(["mcopy", "-i", path, p, "::/"], env)
    restore_apostrophes(path, names)
    if cfg:
        p = os.path.join(OUT, "EZGB.CFG")
        open(p, "w", newline="").write(cfg.replace("\n", "\r\n"))
        sh(["mcopy", "-i", path, p, "::/"], env)


def restore_apostrophes(path, names):
    """mcopy writes ' as _ in long names; put it back in the LFN entries (their
    checksum covers only the 8.3 name). The game files are all zeros, so every
    32-byte slot shaped like an LFN entry is one."""
    assert not any("_" in n for n in names)
    img = bytearray(open(path, "rb").read())
    for e in range(0, len(img), 32):
        if img[e + 11] == 0x0F and img[e + 12] == 0 and img[e + 26:e + 28] == b"\0\0" and 1 <= img[e] & 0x3F <= 20:
            for o in list(range(1, 11, 2)) + list(range(14, 26, 2)) + list(range(28, 32, 2)):
                if img[e + o:e + o + 2] == b"_\0":
                    img[e + o] = ord("'")
    open(path, "wb").write(img)


def capture(exe, boot, kernel, card, script, outdir):
    os.makedirs(outdir, exist_ok=True)
    sp = os.path.join(outdir, "script.txt")
    open(sp, "w").write(script)
    work = os.path.join(outdir, "card.img")
    shutil.copy(card, work)                     # the kernel may write to the card
    sh([exe, boot, kernel, sp, outdir], dict(os.environ, SAMEBOY_EZFLASH_JR_IMG=work))
    return {os.path.basename(p)[:-4]: Image.open(p).convert("RGB") for p in glob.glob(os.path.join(outdir, "*.ppm"))}


def big(im):
    return im.resize((160 * SCALE, 144 * SCALE), Image.NEAREST)


BOOT = "wait 900\n"                             # boot, SD read, sort, first paint


def star(down, shot=None):
    """Move the cursor down `down` rows, hold A for the menu, pick Star."""
    return ("tap DOWN\n" * down + "wait 10\nhold A\nwait 45\nrelease A\nwait 20\ntap DOWN\ntap DOWN\nwait 10\n"
            + (f"shot {shot}\n" if shot else "") + "tap A\nwait 120\n")


# SORT TOP from a fresh cart: Crystal, Link's Awakening, Gold, Silver, Seasons,
# Ages, Mario Deluxe, Red, Blue, Yellow. After a star the list re-sorts and the
# cursor goes back to the top; starred games come first, A to Z.
SCRIPT = (BOOT + "shot list\n"
          + star(6, "menu")                     # Super Mario Bros. Deluxe
          + star(9)                             # Pokemon Yellow
          + star(6)                             # Zelda - Oracle of Seasons
          + "tap DOWN\n" * 4 + "wait 30\nshot starred\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--explore", action="store_true", help="frames every 20 during boot, to find the timing")
    args = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    exe, boot = shot_tool()

    kernel = os.path.join(OUT, "ezgb-dv.gb")
    dat, _ = build.build(build.mod_kernel())
    open(kernel, "wb").write(dat)
    card = os.path.join(OUT, "card.img")
    make_card(card)

    if args.explore:
        script = "".join(f"wait 20\nshot f{n:04d}\n" for n in range(20, 1201, 20))
        shots = capture(exe, boot, kernel, card, script, os.path.join(OUT, "explore"))
        sheet = Image.new("RGB", (160 * 10, 144 * 6), "black")
        for i, key in enumerate(sorted(shots)):
            sheet.paste(shots[key], (160 * (i % 10), 144 * (i // 10)))
        sheet.save(os.path.join(OUT, "explore.png"))
        print("wrote", os.path.join(OUT, "explore.png"))
        return

    shots = capture(exe, boot, kernel, card, SCRIPT, os.path.join(OUT, "shots"))
    os.makedirs(DOCS, exist_ok=True)
    for name in ("list", "menu", "starred"):
        big(shots[name]).save(os.path.join(DOCS, f"{name}.png"))
    print("wrote", DOCS)


if __name__ == "__main__":
    main()
