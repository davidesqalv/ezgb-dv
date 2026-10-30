/* ezgb-dv: modified copy of kernel/src/browser_icons.c. dv/build.py places it at
 * 02:6b80 and points the 00:3ec8 stub there; the inject.py line below is upstream's.
 *
 * Browser row icons (docs/dmg-ui-visibility.md "Change 4", docs/font12.md).
 *
 * Bank 2, injected at 02:7e80 and reached through the 8-byte far stub that
 * now sits at the old bank-0 address 00:3ec8 (`cd 8d 07 80 7e 02 00 c9`), so
 * the six stock name draws in DrawBrowserEntries / DrawBrowserDetail and
 * the scroll-repaint shim still `call $3ec8` with DrawString's (s, len, x,
 * y) frame. The stub is `call`ed, so FarCallTrampoline's three words sit
 * between its return address and the arguments: three pad parameters.
 *
 * Column 0 gets one icon glyph and the name follows from column 1.
 * Directories are recognized by the stock len 0; files come in with len
 * $14. The icon is drawn in whatever ink the row has, so it inverts with
 * the selection bar. Font codes: $C0 folder, $C1 .gb cart, $C2 .gbc cart,
 * $C4 .sav page, $C3 boxed "?" for anything else.
 *
 * Living in bank 2 next to the 12x12 renderer it calls DrawString12 (the
 * far entry, hence the three dummy pads) with a plain near call, one
 * trampoline hop per row instead of two, and it leaves bank 0 free for the
 * upcoming 8px/12px mode switch.
 *
 *   python3 tools/inject.py src/browser_icons.c $V 2 7e80 DrawNameWithIconImpl \
 *       --pin DrawString12=7500 --pin DrawString=08b7 --pin hUiMode=fffb --replace --apply
 */

typedef unsigned char u8;
typedef unsigned int u16;

#define UP(c) ((u8)((c) & 0xDF))   /* case-fold letters (enough for ext compares) */

extern void DrawString12(u16 pad_thunk, u16 pad_af, u16 pad_ret, const u8 *s, u8 len, u8 col, u8 row); /* 02:5800 */
extern volatile u8 wDrawColor;                               /* $d734: ink (StoreDrawParams) */
extern void RecolorIcon(u8 py);                              /* 02:6d60 (asm/bank2_recolor.asm): icon -> ink 2 */

void DrawNameWithIcon(u16 far_pad_thunk, u16 far_pad_af, u16 far_pad_ret, const u8 *s, u8 len, u8 x, u8 y) {
    u8 i, dot, n, e, c1, c2, ic, blue;

    (void)far_pad_thunk;
    (void)far_pad_af;
    (void)far_pad_ret;
    u8 buf[41];

    (void)x;
    if (len == 0) {
        ic = 0xC0;                       /* folder */
        len = 19;
    } else {
        dot = 0xFF;
        for (i = 0; i < 254 && s[i]; i++) if (s[i] == '.') dot = i;
        n = i;
        ic = 0xC3;                       /* boxed "?" */
        if (dot != 0xFF) {
            e = (u8)(n - dot - 1);
            c1 = UP(s[dot + 1]);
            c2 = UP(s[dot + 2]);
            if (c1 == 'G' && c2 == 'B') {
                if (e == 2) ic = 0xC1;                            /* .gb  */
                else if (e == 3 && UP(s[dot + 3]) == 'C') ic = 0xC2;   /* .gbc */
            } else if (e == 3 && c1 == 'S' && c2 == 'A' && UP(s[dot + 3]) == 'V') {
                ic = 0xC4;               /* .sav page */
            }
        }
        len--;
        if (s[252] == 0x5A) ic = 0x7F;   /* ezjr: starred (MarkStars marks byte 252) */
    }
    /* ezjr custom build (12px only): one pass for icon + name, as the mod
     * draws it; on a normal row (ink 3) the icon is then turned blue in VRAM
     * (RecolorIcon, 12 plane-0 writes), much cheaper than a second pass. */
    (void)len;
    blue = wDrawColor == 3;
    buf[0] = ic;
    for (i = 0; i < 39; i++) {
        buf[1 + i] = s[i];
        if (s[i] == 0) {
            break;
        }
    }
    buf[40] = 0;
    DrawString12(0, 0, 0, buf, 0, 0, y);
    if (blue) {
        RecolorIcon((u8)(20 + 12 * (y - 2)));
    }
}
