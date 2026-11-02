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
 * down, the new row 0 highlighted and row 1 plain going up.
 *
 * A move that keeps the window (a row down or up, or a wrap on a list that
 * fits one page) draws no text at all: MoveHighlight (move_highlight.c, bank
 * 2, through MoveHighlightStub at 00:3e9c) recolors the old and the new row
 * in VRAM, draws the counter and leaves dirty 0. It declines when the bar's
 * long name has scrolled since the last move; then the move goes to the
 * stock repaint as before (dirty 2 or 3, or 1 for a wrap, whose rows are not
 * next to each other). Every move leaves all rows showing their names from
 * the start, so afterwards the marquee's last index goes back to its boot
 * value, which is how MoveHighlight tells. A wrap on a longer list shows ten
 * new entries and still redraws the page (dirty 1).
 *
 * Key repeat. The browser reports a held D-pad key on every pass of its
 * loop, and the stock loop had no repeat delay of its own: a move simply
 * took long enough (about 13 frames) that a tap was over before the next
 * pass. A recolored move takes about 2, so a tap could move twice. Now a
 * press moves at once, and a key that was already down at the previous poll
 * (RomMenuPadTrack keeps that report at $fff5) moves again only after
 * REPEAT_DELAY frames, then every REPEAT_RATE.
 */
#define ROWS 10
#define ENTRY_COUNT (*(volatile unsigned int *)0xc2a2)
#define LIST_Y 20                   /* pixel y of list row 0 */
#define ROW_H 12
#define MOVED (8 * ROW_H / 4)       /* rows 1..8, in 4-pixel-row groups */
#define UP_SRC_Y 124                /* going up, bottom first: the last group of rows 1..8 (y 32..127) */
#define UP_DST_Y 136                /* ...and where it goes, ROW_H lower */
#define MQ_LAST (*(volatile unsigned int *)0xcc31)   /* DrawDirEntryLabel's last drawn index */
#define MQ_CLEAN 0xEEEE                              /* its boot value: nothing scrolled */
#define PAD_PREV (*(volatile unsigned char *)0xfff5) /* RomMenuPadTrack: the previous poll's report */
#define HFRAME   (*(volatile unsigned char *)0xfffa) /* +1 per VBlank */
#define HOLD_T   (*(volatile unsigned char *)0xfff2) /* hFrame at the press, moved on at each repeat (HRAM no code uses) */
#define PAD_UP   0x04
#define PAD_DOWN 0x08
#define REPEAT_DELAY 18                              /* frames held before the first repeat (0.3 s) */
#define REPEAT_RATE  6                               /* frames between repeats */

extern void ShiftRows(unsigned char dst_y, unsigned char src_y, unsigned char batches, signed char step);  /* 05:7680 */

struct BrowserScrollState {
    unsigned char dirty;            /* 0 none, 1 full page, 2 row-down, 3 row-up */
    unsigned int base;              /* first visible entry */
    unsigned char sel;              /* row within the window */
};

extern unsigned char MoveHighlightStub(struct BrowserScrollState *st, unsigned char to);  /* 00:3e9c -> 02 MoveHighlight */

/* The bar to row `to` of the same window: recolored, or the stock repaint. */
static void move_in_page(struct BrowserScrollState *st, unsigned char to, unsigned char dirty) {
    if (!MoveHighlightStub(st, to)) {
        st->sel = to;
        st->dirty = dirty;
    }
}

static void down(struct BrowserScrollState *st) {
    unsigned int base = st->base;
    unsigned char sel = st->sel;

    if (base + sel + 1 >= ENTRY_COUNT) {
        if (base == 0) {                /* the whole list is on the page */
            move_in_page(st, 0, 1);
            return;
        }
        st->base = 0;
        st->sel = 0;
        st->dirty = 1;
        return;
    }
    if (sel + 1 < ROWS) {
        move_in_page(st, sel + 1, 2);
        return;
    }
    st->base = base + 1;
    ShiftRows(LIST_Y, LIST_Y + ROW_H, MOVED, 4);                                    /* rows 1..8 -> 0..7 */
    st->dirty = 2;
}

static void up(struct BrowserScrollState *st) {
    unsigned char sel = st->sel;
    unsigned int n;

    if (sel != 0) {
        move_in_page(st, sel - 1, 3);
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
    if (n <= ROWS) {                    /* the whole list is on the page */
        move_in_page(st, (unsigned char)(n - 1), 1);
        return;
    }
    st->base = n - ROWS;
    st->sel = ROWS - 1;
    st->dirty = 1;
}

/* 1 when this report of `key` should move: a press, or a key held for
 * REPEAT_DELAY frames, then every REPEAT_RATE. */
static unsigned char repeat_ok(unsigned char key) {
    unsigned char now = HFRAME;

    if (!(PAD_PREV & key)) {
        HOLD_T = now;
        return 1;
    }
    if ((unsigned char)(now - HOLD_T) < REPEAT_DELAY) {
        return 0;
    }
    HOLD_T = (unsigned char)(now - (REPEAT_DELAY - REPEAT_RATE));
    return 1;
}

void ezjr_scroll_down(unsigned int p0, unsigned int p1, unsigned int p2, struct BrowserScrollState *st) {
    (void)p0; (void)p1; (void)p2;
    if (repeat_ok(PAD_DOWN)) {
        down(st);
        MQ_LAST = MQ_CLEAN;
    }
}

void ezjr_scroll_up(unsigned int p0, unsigned int p1, unsigned int p2, struct BrowserScrollState *st) {
    (void)p0; (void)p1; (void)p2;
    if (repeat_ok(PAD_UP)) {
        up(st);
        MQ_LAST = MQ_CLEAN;
    }
}
