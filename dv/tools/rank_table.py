"""Base-score table for SORT TOP: hash each ranked filename like the cart does."""
import os

BASE_TOP, STEP = 125, 2

def name_hash(name):
    """16-bit djb2 over the uppercased filename (matches Hash in asm/bank5.asm)."""
    h = 5381
    for ch in name.encode("latin-1"):
        if 0x61 <= ch <= 0x7A:
            ch -= 0x20
        h = (h * 33 + ch) & 0xFFFF
    return h

def load(path=os.path.join(os.path.dirname(__file__), "ranking.txt")):
    names = [l.strip() for l in open(path) if l.strip() and not l.startswith("#")]
    rows = [(n, name_hash(n), max(1, BASE_TOP - STEP * i)) for i, n in enumerate(names)]
    hashes = [h for _, h, _ in rows]
    dupes = {h for h in hashes if hashes.count(h) > 1}
    if dupes:
        raise SystemExit(f"hash collision in ranking.txt: {[n for n, h, _ in rows if h in dupes]}")
    return rows

def table_bytes(rows):
    """count byte, then hash lo, hash hi, base per game."""
    out = bytearray([len(rows)])
    for _, h, base in rows:
        out += bytes((h & 0xFF, h >> 8, base))
    return bytes(out)

if __name__ == "__main__":
    rows = load()
    for n, h, b in rows[:5]: print(f"{h:04x} {b:3} {n}")
    print(len(rows), "games,", len(table_bytes(rows)), "bytes")
