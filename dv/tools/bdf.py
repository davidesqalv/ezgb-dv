"""Minimal BDF reader: glyph cells for a fixed-size bitmap font."""
def load(path):
    asc = desc = 0; glyphs = {}; cur = None; bits = None
    for line in open(path, encoding="latin-1"):
        p = line.split()
        if not p: continue
        k = p[0]
        if k == "FONT_ASCENT": asc = int(p[1])
        elif k == "FONT_DESCENT": desc = int(p[1])
        elif k == "ENCODING": cur = {"code": int(p[1])}
        elif k == "DWIDTH" and cur is not None: cur["dw"] = int(p[1])
        elif k == "BBX" and cur is not None: cur["bbx"] = tuple(map(int, p[1:5]))
        elif k == "BITMAP": bits = []
        elif k == "ENDCHAR":
            cur["bits"] = bits; glyphs[cur["code"]] = cur; cur = None; bits = None
        elif bits is not None: bits.append(int(k, 16) if k else 0)
    return asc, desc, glyphs

def cell(font, code, rows=12, top_pad=0):
    """Return rows x dwidth list of 0/1 pixels, baseline at row asc-1+top_pad."""
    asc, desc, glyphs = font
    g = glyphs.get(code) or glyphs.get(ord("?"))
    w, h, xo, yo = g["bbx"]; dw = g.get("dw", w)
    nbits = ((w + 7) // 8) * 8
    out = [[0] * dw for _ in range(rows)]
    top = asc - (yo + h) + top_pad
    for r, v in enumerate(g["bits"]):
        y = top + r
        if not 0 <= y < rows: continue
        for c in range(w):
            if v >> (nbits - 1 - c) & 1:
                x = xo + c
                if 0 <= x < dw: out[y][x] = 1
    return out
