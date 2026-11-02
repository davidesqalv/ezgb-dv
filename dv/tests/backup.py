#!/usr/bin/env python3
"""Daily save backup (dv/src/auto_backup.c), end to end: boot the menu in
SameBoy's core (the repo's EZ Flash Jr patch) with a test SD card and a save
waiting in the cart's battery RAM, then read /SAVER back off the card.

    scripts/setup-sameboy.sh && make -C tools/SameBoy CONF=debug sdl   # once
    brew install mtools
    python3 dv/tests/backup.py

The patched core reads its clock from the host, so a file dated yesterday is
a save from before today.
"""
import datetime
import glob
import hashlib
import os
import shutil
import subprocess
import sys
import time

TESTS = os.path.dirname(os.path.abspath(__file__))
DV = os.path.dirname(TESTS)
REPO = os.path.dirname(DV)
SAMEBOY = os.path.join(REPO, "tools", "SameBoy")
OUT = os.path.join(DV, "build", "tests", "backup")
sys.path.insert(0, DV)
import build                                    # noqa: E402

ENV = dict(os.environ, MTOOLS_SKIP_CHECK="1")
BANK = 0x2000
A, B, C, D = (bytes([v]) * BANK for v in (0x11, 0x22, 0x33, 0x44))
NAMES = {A: "A", B: "B", C: "C", D: "D"}
YESTERDAY = time.mktime((datetime.date.today() - datetime.timedelta(days=1)).timetuple()) + 12 * 3600
LAST_WEEK = YESTERDAY - 5 * 86400


def sh(*cmd, env=ENV):
    r = subprocess.run(cmd, capture_output=True, text=True, env=env)
    if r.returncode:
        raise SystemExit(f"{' '.join(cmd)} failed:\n{r.stdout}{r.stderr}")
    return r.stdout


def tools():
    """The menu build and dv/showcase's headless SameBoy runner."""
    boot = os.path.join(SAMEBOY, "build", "bin", "SDL", "dmg_boot.bin")
    objs = glob.glob(os.path.join(SAMEBOY, "build", "obj", "Core", "*.o"))
    if not os.path.exists(boot) or not objs:
        raise SystemExit("SameBoy isn't built: scripts/setup-sameboy.sh, then make -C tools/SameBoy CONF=debug sdl")
    os.makedirs(OUT, exist_ok=True)
    shot = os.path.join(OUT, "shot")
    sh("cc", "-O2", "-I", SAMEBOY, "-o", shot, os.path.join(DV, "showcase", "shot.c"), *objs, "-lm")
    kernel = os.path.join(OUT, "ezgb-dv.gb")
    dat, _ = build.build(build.mod_kernel())
    open(kernel, "wb").write(dat)
    return shot, boot, kernel


def card(saves):
    """64 MiB FAT32 card: two games, AUTO SAVE on, and /SAVER/<name> -> (data, mtime or None for now)."""
    work = os.path.join(OUT, "card")
    shutil.rmtree(work, ignore_errors=True)
    os.makedirs(work)
    img = os.path.join(work, "card.img")
    with open(img, "wb") as f:
        f.truncate(64 << 20)
    sh("mformat", "-i", img, "-F", "-v", "EZJR", "::")
    for name in ("Test.gb", "Zelda.gb"):
        p = os.path.join(work, name)
        open(p, "wb").write(bytes(32 << 10))
        sh("mcopy", "-i", img, p, "::/")
    p = os.path.join(work, "EZGB.CFG")
    open(p, "w", newline="").write("AUTOSAVE=1\r\n")
    sh("mcopy", "-i", img, p, "::/")
    sh("mmd", "-i", img, "::/SAVER")
    for name, (data, mtime) in saves.items():
        p = os.path.join(work, name)
        open(p, "wb").write(data)
        if mtime:
            os.utime(p, (mtime, mtime))
        sh("mcopy", "-m", "-i", img, p, "::/SAVER/")
    return work


def cart_ram(work, save, pending=True, backup_on=None):
    """The battery pSRAM beside card.img: Test.gb's 8 KB save on page $00 and,
    on page $11, the stamp a launch leaves (docs/psram-save-map.md) and, when
    backup_on is given, the SET tab's DAILY BACKUP record at $B108."""
    ps = bytearray(b"\xff" * (64 * BANK))
    meta, path = 0x11 * BANK, b"/SAVER/Test.sav"
    ps[meta] = 0xAA if pending else 0x00            # backup pending
    ps[meta + 0x001] = 1                            # size in 8 KB banks
    ps[meta + 0x00F] = len(path)
    ps[meta + 0x010:meta + 0x010 + len(path)] = path
    ps[meta + 0x200] = 1                            # AUTO SAVE
    ps[meta + 0x201] = 0x88                         # battery canary
    if backup_on is not None:
        ps[meta + 0x1108:meta + 0x110C] = bytes((ord("B"), ord("K"), backup_on, backup_on ^ 0xFF))
    ps[:len(save)] = save
    open(os.path.join(work, "psram.bin"), "wb").write(ps)


def boot(tool, work, frames=1500):
    shot, bootrom, kernel = tool
    script = os.path.join(work, "script.txt")
    open(script, "w").write(f"wait {frames}\n")
    sh(shot, bootrom, kernel, script, work, env=dict(ENV, SAMEBOY_EZFLASH_JR_IMG=os.path.join(work, "card.img")))


def saver(work):
    """/SAVER as (name, content), backups of Test as BK."""
    img = os.path.join(work, "card.img")
    out = []
    for line in sh("mdir", "-i", img, "-b", "::/SAVER").splitlines():
        name = line.strip().split("/")[-1]
        if not name:
            continue
        dst = os.path.join(work, "out.bin")
        sh("mcopy", "-n", "-i", img, "::/SAVER/" + name, dst)
        data = open(dst, "rb").read()
        out.append(("BK" if name.startswith("Test 20") else name, NAMES.get(data, hashlib.md5(data).hexdigest()[:8])))
    return sorted(out)


def main():
    tool = tools()
    failures = 0

    def check(work, title, expect):
        nonlocal failures
        got = saver(work)
        if got == sorted(expect):
            print(f"ok   {title}")
        else:
            failures += 1
            print(f"FAIL {title}\n     got  {got}\n     want {sorted(expect)}")

    w = card({"Test.sav": (A, YESTERDAY)})
    cart_ram(w, B)
    boot(tool, w)
    check(w, "a save from yesterday is backed up, then overwritten", [("BK", "A"), ("Test.sav", "B")])
    cart_ram(w, C)
    boot(tool, w)
    check(w, "the next boot the same day keeps that backup", [("BK", "A"), ("Test.sav", "C")])
    cart_ram(w, D)
    boot(tool, w)
    check(w, "and the one after", [("BK", "A"), ("Test.sav", "D")])

    w = card({"Test.sav": (A, YESTERDAY), "Test 2026-10-20 12-00.sav": (C, LAST_WEEK),
              "Test 2026-10-25 12-00.sav": (D, LAST_WEEK)})
    cart_ram(w, B)
    boot(tool, w, frames=1800)
    check(w, "older backups give way to the new one", [("BK", "A"), ("Test.sav", "B")])

    w = card({})
    cart_ram(w, C)
    boot(tool, w)
    check(w, "a game's first save: nothing to back up", [("Test.sav", "C")])

    w = card({"Test.sav": (A, YESTERDAY)})
    cart_ram(w, B, pending=False)
    boot(tool, w)
    check(w, "no game launched: nothing changes", [("Test.sav", "A")])

    w = card({"Test.sav": (A, YESTERDAY), "Other.sav": (B, YESTERDAY), "Other 2026-10-01 12-00.sav": (C, LAST_WEEK)})
    cart_ram(w, D)
    boot(tool, w)
    check(w, "other games' saves are left alone",
          [("BK", "A"), ("Other 2026-10-01 12-00.sav", "C"), ("Other.sav", "B"), ("Test.sav", "D")])

    w = card({"Test.sav": (A, YESTERDAY)})
    cart_ram(w, B, backup_on=0)
    boot(tool, w)
    check(w, "DAILY BACKUP unticked: no backup", [("Test.sav", "B")])

    w = card({"Test.sav": (A, YESTERDAY)})
    cart_ram(w, B, backup_on=1)
    boot(tool, w)
    check(w, "DAILY BACKUP ticked: backed up", [("BK", "A"), ("Test.sav", "B")])

    print(f"\n{9 - failures} passed, {failures} failed")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
