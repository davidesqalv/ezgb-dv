/* ezgb-dv: DOWN/UP in the file browser, with wrap-around.
 *
 * Replaces browser_scroll.c's DOWN entry (00:3ed0) and the UP code the hook at
 * 00:02f0 calls (00:3fbb), which become 8-byte far stubs (`cd 8d 07 <addr> 05 00 c9`) into this bank-5 block.
 * Reached through a `call`ed stub, so FarCallTrampoline's three words sit
 * between the caller's return and the argument: three pad parameters.
 *
 * 12px only (10 rows). The whole directory is enumerated before the first
 * draw (browser_sort.c), so the old "stream another DirList batch" fallback is
 * gone. DOWN on the last entry goes to the top; UP on the first goes to the
 * last, with the window on the final page.
 *
 * A one-row scroll (the cursor on the bottom row going down, or the top row
 * going up) used to set dirty 1 and redraw all ten rows, about 3 frames each
 * in the 12px renderer. Eight of them only move: ShiftRows (bank5.asm) moves
 * their pixels in VRAM, and the scroll is passed on as an ordinary row move
 * (dirty 2 or 3), whose stock repaint draws just the two rows around the
 * cursor and the counter: row 8 plain and the new row 9 highlighted going
 * down, the new row 0 highlighted and row 1 plain going up. Wraps still
 * redraw the page.
 */
#define ROWS 10
#define ENTRY_COUNT (*(volatile unsigned int *)0xc2a2)
#define LIST_Y 20                   /* pixel y of list row 0 */
#define ROW_H 12
#define MOVED (8 * ROW_H / 4)       /* rows 1..8, in 4-pixel-row groups */
#define UP_SRC_Y 124                /* going up, bottom first: the last group of rows 1..8 (y 32..127) */
#define UP_DST_Y 136                /* ...and where it goes, ROW_H lower */

extern void ShiftRows(unsigned char dst_y, unsigned char src_y, unsigned char batches, signed char step);  /* 05:7680 */

struct BrowserScrollState {
    unsigned char dirty;            /* 0 none, 1 full page, 2 row-down, 3 row-up */
    unsigned int base;              /* first visible entry */
    unsigned char sel;              /* row within the window */
};

void ezjr_scroll_down(unsigned int p0, unsigned int p1, unsigned int p2, struct BrowserScrollState *st) {
    unsigned int base = st->base;
    unsigned char sel = st->sel;

    (void)p0; (void)p1; (void)p2;
    if (base + sel + 1 >= ENTRY_COUNT) {
        st->base = 0;
        st->sel = 0;
        st->dirty = 1;
        return;
    }
    if (sel + 1 < ROWS) {
        st->sel = sel + 1;
        st->dirty = 2;
        return;
    }
    st->base = base + 1;
    ShiftRows(LIST_Y, LIST_Y + ROW_H, MOVED, 4);                                    /* rows 1..8 -> 0..7 */
    st->dirty = 2;
}

void ezjr_scroll_up(unsigned int p0, unsigned int p1, unsigned int p2, struct BrowserScrollState *st) {
    unsigned char sel = st->sel;
    unsigned int n;

    (void)p0; (void)p1; (void)p2;
    if (sel != 0) {
        st->sel = sel - 1;
        st->dirty = 3;
        return;
    }
    if (st->base != 0) {
        st->base = st->base - 1;
        ShiftRows(UP_DST_Y, UP_SRC_Y, MOVED, -4);                                       /* rows 8..1 -> 9..2 */
        st->dirty = 3;
        return;
    }
    n = ENTRY_COUNT;
    if (n == 0) {
        return;
    }
    if (n > ROWS) {
        st->base = n - ROWS;
        st->sel = ROWS - 1;
    } else {
        st->base = 0;
        st->sel = (unsigned char)(n - 1);
    }
    st->dirty = 1;
}
