/* ezgb-dv: modified copy of kernel/src/flcfg.c. The rows below AUTO SAVE are
 * reordered: DAILY BACKUP (a new pSRAM switch auto_backup.c reads, on by
 * default) in place of the UI row (ezgb-dv is 12px only), then SORT A-Z (the
 * old SGB BOOT row, its record at page $11 $B100, which bank5.asm reads),
 * then FAST LAUNCH and PICK ROM. 12px only, with settext.c's copy giving the
 * pane a left margin. dv/build.py places it at 04:6600; the inject.py line in
 * scripts/inject-ezcfg.sh is upstream's.
 *
 * Fast-launch configuration from the SET tab (docs/fastlaunch-set-tab.md).
 *
 * Bank 4, injected at 04:6600, same bank as DrawTimeAutosaveScreen (04:46f4)
 * so the hand-assembled hook shims (04:5932..) reach it with a plain call.
 * The SD file /EZGB.CFG is the single source of truth, read and written by
 * the shared bank-2 module ezcfg.c (docs/ezgb-cfg.md) through the bank-4
 * FarCallEzCfg shim (04:5f00); this file only owns the FL_* WRAM state and
 * the SET-tab UI:
 *
 *   FLAUNCH=<path>       -> enabled, launch that ROM
 *   FLAUNCH=#<path>      -> DISABLED (every trigger skipped), path kept
 *   missing / empty      -> enabled, no explicit target (lone-ROM rule, see
 *                           fastlaunch.c)
 *
 * One entry point, op-selected (inject.py pins the first-declared function):
 *
 *   op 0 ENTER  SET prologue: cancel any pending pick, load the file, draw
 *               the mod rows (RTC SD / NO SD, the DAILY BACKUP, SORT A-Z and
 *               FAST LAUNCH checkboxes, the ROM name + PICK ROM button) with
 *               the cursor highlight.
 *   op 1 ROWS   cursor moved (hiliteDec/hiliteInc tails): redraw the rows.
 *   op 2 A      A pressed with the cursor on a mod row. RTC and FAST LAUNCH
 *               toggle and rewrite the file (returns 0 = jp redraw); DAILY
 *               BACKUP and SORT A-Z toggle their pSRAM records instead (no
 *               file); PICK ROM arms pick mode (returns 1 = leave the SET
 *               screen; the bank-0 FlSetExitHook then re-enters the browser).
 *   op 3 PICK   the browser's A-on-ROM hook (bank 0, via FlPickCommitFar):
 *               compose $c2a6 + '/' + $c4a4, rewrite the file, disarm.
 *   op 4 LOAD   test hook only.
 *   op 5 TICK   once per pass of the SET input loop (SetLoopTickHook,
 *               04:5f20, on its ReadJoypad call): scroll the ROM name.
 *
 * Layout (tile rows, y = 8 * row; the stock rows were slid up one, see
 * inject-ezcfg.sh):
 *   2 TIME: [SET]   4 date/time   6 RTC: SD [ ] NO SD [ ]   8 AUTO SAVE: [ ]
 *   10 DAILY BACKUP: [ ]   12 SORT A-Z: [ ]   14 FAST LAUNCH: [ ]
 *   16 <name, 10 cols, scrolling> [PICK ROM]
 * `frame` is DrawTimeAutosaveScreen's stack frame (frame[0x3d] = cursor row:
 * 0 TIME SET, 1 RTC, 2 AUTO SAVE, 3 DAILY BACKUP, 4 SORT A-Z, 5 FAST LAUNCH,
 * 6 PICK ROM), the same seven rows the stock cursor walks.
 *
 * DAILY BACKUP and SORT A-Z are not in EZGB.CFG but in battery-backed pSRAM,
 * page $11, next to the play table (bank5.asm): SORT A-Z at $B100 ('S', 'G',
 * flag, ~flag; ticked = A-Z), DAILY BACKUP at $B108 ('B', 'K', flag, ~flag;
 * anything else, as on a fresh cart, = on). NULL for op 3/4/5.
 *
 * ezcfg leaves $7FC0=$00 after its SD I/O. The SET screen rests at $7FC0=$00,
 * so nothing to restore there; after a pick the SET prologue re-selects its
 * own pages. ReadJoypad is level triggered, so every A action spins until A
 * is released; otherwise the screen we hand over to sees the same press.
 */

typedef unsigned char u8;
typedef unsigned int u16;

extern void FarCallEzCfg(void);                                     /* 04:5f00 -> ezcfg (02:4a00) */
extern void SetFpgaPage_B4(u8 page);                                /* 04:466e: $7FC0 = page */
extern void DrawString(const u8 *s, u8 len, u8 col, u8 row);        /* 00:08b7 */
extern void DrawRect(u8 x0, u8 y0, u8 x1, u8 y1, u8 fill);          /* 00:27ba */
extern void SetText(const u8 *s, u8 len, u8 col, u8 row);           /* 04:6400, settext.c: DrawString, or the 12px pane's fields */
extern void StoreDrawParams(u8 color, u8 colorB, u8 op);            /* 00:2791 */
extern u8 ReadJoypad(void);                                         /* 00:3a4a, post-swap byte, A = $10 */

#define FL_EN    (*(volatile u8 *)0xDA80)
#define FL_PLEN  (*(volatile u8 *)0xDA81)
#define FL_PATH  ((u8 *)0xDA82)     /* stored path, NUL-terminated, <= PATH_MAX */
#define FL_DISP  ((u8 *)0xDB10)     /* 40-byte zero-padded display buffer */
#define EZ_OP    (*(volatile u8 *)0xDBFC)
#define FL_PICK  (*(volatile u8 *)0xDBFE)
#define CWD      ((u8 *)0xC2A6)     /* browser: current directory ("/" or "/a/b") */
#define SELNAME  ((u8 *)0xC4A4)     /* browser: selected entry name */

#define OP_LOAD  0
#define OP_SAVE  1

#define PATH_MAX  120
#define DISP_LEN  40

#define ROW_RTC    1         /* RTC: SD / NO SD (RTC backup, restore and prompt on or off);
                              * row 2 is the stock AUTO SAVE, which never reaches flcfg */
#define ROW_BACKUP 3         /* DAILY BACKUP: checkbox, a pSRAM record */
#define ROW_SORT   4         /* SORT A-Z: checkbox, a pSRAM record */
#define ROW_CHECK  5         /* FAST LAUNCH */
#define ROW_PICK   6
#define RAM_PAGE (*(volatile u8 *)0x4000)  /* pSRAM page latch, under $7FC0 = $03 */
#define SORT_REC   ((volatile u8 *)0xB100) /* page $11: 'S', 'G', flag, ~flag */
#define BACKUP_REC ((volatile u8 *)0xB108) /* page $11: 'B', 'K', flag, ~flag */
#define RTC_OFF  (*(volatile u8 *)0xDB3A)   /* RTCSD=0, owned by ezcfg */
#define MQ_POS   (*(volatile u8 *)0xDB38)   /* name marquee: first shown char */
#define MQ_TICK  (*(volatile u8 *)0xDB39)   /* ...frames since the last step */
#define MQ_FR    (*(volatile u8 *)0xDB3B)   /* hFrame at the previous tick */
#define HFRAME   (*(volatile u8 *)0xFFFA)   /* +1 per VBlank (VBlankPadLatch, 00:05cf) */
#define NAME_W   10                         /* name columns left of PICK ROM */
#define MQ_GAP   3                          /* blanks between repeats */
#define MQ_RATE  20                         /* frames per step (3 chars/s) */
#define MQ_HOLD  60                         /* ...at the start of the name (1 s) */

static void cfg_load(void);
static void cfg_save(void);
static void draw_static(void);
static void draw_name(void);
static void draw_rows(u8 cur);
static void pick_commit(void);
static void wait_a_release(void);
static void box(u8 x, u8 y, u8 on, u8 hi);
static u8 rec_get(volatile u8 *rec, u8 sig0, u8 sig1, u8 none);
static void rec_set(volatile u8 *rec, u8 sig0, u8 sig1, u8 on);

u8 flcfg(u8 *frame, u8 op) {
    if (op == 0) {
        FL_PICK = 0;
        MQ_POS = 0;
        MQ_TICK = 0;
        MQ_FR = HFRAME;
        cfg_load();
        draw_static();
        draw_rows(frame[0x3d]);
        SetFpgaPage_B4(0);
        return 0;
    }
    if (op == 1) {
        draw_rows(frame[0x3d]);
        return 0;
    }
    if (op == 2) {
        if (frame[0x3d] == ROW_CHECK) {
            FL_EN = FL_EN ? 0 : 1;
            cfg_save();
            draw_rows(ROW_CHECK);
            wait_a_release();
            SetFpgaPage_B4(0);
            return 0;
        }
        if (frame[0x3d] == ROW_RTC) {
            RTC_OFF = RTC_OFF ? 0 : 1;
            cfg_save();
            draw_rows(ROW_RTC);
            wait_a_release();
            SetFpgaPage_B4(0);
            return 0;
        }
        if (frame[0x3d] == ROW_SORT) {
            rec_set(SORT_REC, 'S', 'G', !rec_get(SORT_REC, 'S', 'G', 0));
            draw_rows(ROW_SORT);
            wait_a_release();
            return 0;
        }
        if (frame[0x3d] == ROW_BACKUP) {
            rec_set(BACKUP_REC, 'B', 'K', !rec_get(BACKUP_REC, 'B', 'K', 1));
            draw_rows(ROW_BACKUP);
            wait_a_release();
            return 0;
        }
        FL_PICK = 1;
        wait_a_release();
        return 1;
    }
    if (op == 3) {
        pick_commit();
        return 0;
    }
    if (op == 5) {
        /* Paced in frames, not loop passes: a pass takes anything from a
         * fraction of a frame (1.05e) to exactly one (1.04e waits for VBlank
         * each pass), so count the VBlank interrupt's frame counter. */
        u8 f = HFRAME, d = f - MQ_FR;
        MQ_FR = f;
        if (d > 100) d = 100;             /* MQ_TICK stays below 256 */
        MQ_TICK += d;
        if (MQ_TICK >= (MQ_POS == 0 ? MQ_HOLD : MQ_RATE)) {
            MQ_TICK = 0;
            MQ_POS++;
            draw_name();          /* wraps MQ_POS, redraws only when it scrolls */
        }
        return 0;
    }
    cfg_load();
    return 0;
}

/* /EZGB.CFG -> FL_EN / FL_PLEN / FL_PATH (and the RTC copy, unused here). */
static void cfg_load(void) {
    EZ_OP = OP_LOAD;
    FarCallEzCfg();
}

/* FL_* (+ the RTC copy loaded alongside) -> /EZGB.CFG. */
static void cfg_save(void) {
    EZ_OP = OP_SAVE;
    FarCallEzCfg();
}

/* Browser A-on-ROM in pick mode: CWD + '/' + SELNAME becomes the new path.
 * The enable flag is preserved (a pick does not switch fast launch on). Too
 * long a path (> PATH_MAX) leaves the file untouched. */
static void pick_commit(void) {
    u8 lc, ln, need, n, i;

    cfg_load();                       /* refresh FL_EN (and the RTC line) from the file */

    for (lc = 0; CWD[lc]; lc++) {}
    for (ln = 0; SELNAME[ln]; ln++) {}
    need = lc + ln;
    if (lc == 0 || CWD[lc - 1] != '/') need++;
    if (need <= PATH_MAX) {
        n = 0;
        for (i = 0; i < lc; i++) FL_PATH[n++] = CWD[i];
        if (n == 0 || FL_PATH[n - 1] != '/') FL_PATH[n++] = '/';
        for (i = 0; i < ln; i++) FL_PATH[n++] = SELNAME[i];
        FL_PATH[n] = 0;
        FL_PLEN = n;
        cfg_save();
    }
    FL_PICK = 0;
    wait_a_release();
}

/* A switch record on page $11 (sig0, sig1, flag, ~flag), mapped the way the
 * kernel maps the page for its AUTO SAVE flag (04:58d6): page latch, $7FC0 =
 * $03, access, then both back to 0, where the SET screen rests. A record
 * that isn't one reads as `none`. */
static u8 rec_get(volatile u8 *rec, u8 sig0, u8 sig1, u8 none) {
    u8 on = none;
    RAM_PAGE = 0x11;
    SetFpgaPage_B4(3);
    if (rec[0] == sig0 && rec[1] == sig1 && (rec[2] == 0 || rec[2] == 1) && rec[3] == (u8)~rec[2])
        on = rec[2];
    RAM_PAGE = 0;
    SetFpgaPage_B4(0);
    return on;
}

static void rec_set(volatile u8 *rec, u8 sig0, u8 sig1, u8 on) {
    RAM_PAGE = 0x11;
    SetFpgaPage_B4(3);
    rec[0] = sig0;
    rec[1] = sig1;
    rec[2] = on;
    rec[3] = ~on;
    RAM_PAGE = 0;
    SetFpgaPage_B4(0);
}

static void wait_a_release(void) {
    while (ReadJoypad() & 0x10) {}
}

/* Labels; the name is drawn by draw_name. */
static void draw_static(void) {
    static const u8 rtc_label[5] = {'R','T','C',':',0};
    static const u8 sd_label[3] = {'S','D',0};
    static const u8 nosd_label[6] = {'N','O',' ','S','D',0};
    static const u8 bk_label[14] = {'D','A','I','L','Y',' ','B','A','C','K','U','P',':',0};
    static const u8 sort_label[10] = {'S','O','R','T',' ','A','-','Z',':',0};
    static const u8 fl_label[13] = {'F','A','S','T',' ','L','A','U','N','C','H',':',0};
    StoreDrawParams(3, 0, 0);
    SetText(rtc_label, 4, 0, 6);
    SetText(sd_label, 2, 6, 6);
    SetText(nosd_label, 5, 11, 6);
    SetText(bk_label, 13, 0, 10);
    SetText(sort_label, 9, 0, 12);
    SetText(fl_label, 12, 0, 14);
    draw_name();
}

/* Basename of FL_PATH (or "(AUTO)" when there is no explicit path) in the
 * NAME_W columns left of the PICK ROM button on row 16. A longer name scrolls
 * continuously, cursor or not: MQ_POS is the first character shown, the text
 * repeats after MQ_GAP blanks, and op TICK advances it. DrawString renders
 * NUL as a space up to len, so the window always overwrites what was there. */
static void draw_name(void) {
    static const u8 auto_str[7] = {'(','A','U','T','O',')',0};
    const u8 *src;
    u8 i, k, len, base;

    if (FL_PLEN == 0) {
        src = auto_str;
    } else {
        base = 0;
        for (i = 0; FL_PATH[i]; i++) if (FL_PATH[i] == '/') base = i + 1;
        src = FL_PATH + base;
    }
    for (len = 0; src[len]; len++) {}
    /* the field is 78 px, which ten glyphs can overrun; scroll from ten
     * characters up rather than clip the last one */
    if (len < NAME_W) {
        MQ_POS = 0;
        for (i = 0; i < NAME_W; i++) FL_DISP[i] = i < len ? src[i] : 0;
    } else {
        if (MQ_POS >= len + MQ_GAP) MQ_POS = 0;
        k = MQ_POS;
        for (i = 0; i < NAME_W; i++) {
            FL_DISP[i] = k < len ? src[k] : ' ';
            if (++k >= len + MQ_GAP) k = 0;
        }
    }
    StoreDrawParams(3, 0, 0);
    SetText(FL_DISP, NAME_W, 0, 16);
}

/* Checkbox at pixel x, row y/8 (the stock AUTO SAVE sequence, 04:496a, at
 * x $82; one row up is y $30): clear, outline (highlighted when the cursor is
 * on it), tick. ezgb-dv's colors written out (ink 1 is green), not left to
 * dv/build.py's pattern patch. */
static void box(u8 x, u8 y, u8 on, u8 hi) {
    StoreDrawParams(0, 0, 0);
    DrawRect(x, y, x + 8, y + 8, 1);
    if (hi) StoreDrawParams(1, 1, 0); else StoreDrawParams(3, 0, 0);
    DrawRect(x, y, x + 8, y + 8, 0);
    if (on) {
        StoreDrawParams(1, 1, 0);
        DrawRect(x + 2, y + 2, x + 6, y + 6, 1);
    }
}

/* RTC (row 6: "SD [ ]  NO SD [ ]", one of the two ticked; A switches), the
 * DAILY BACKUP (row 10), SORT A-Z (row 12) and FAST LAUNCH (row 14)
 * checkboxes, and the PICK ROM button on row 16, shaped like the stock SET
 * button (the text row plus a pixel above and below), black on green when
 * the cursor is on it. */
static void draw_rows(u8 cur) {
    static const u8 pick_str[9] = {'P','I','C','K',' ','R','O','M',0};

    box(0x42, 0x30, !RTC_OFF, cur == ROW_RTC);   /* after "SD" (cols 6-7) */
    box(0x82, 0x30, RTC_OFF, cur == ROW_RTC);    /* after "NO SD" (cols 11-15) */
    box(0x82, 0x50, rec_get(BACKUP_REC, 'B', 'K', 1), cur == ROW_BACKUP);
    box(0x82, 0x60, rec_get(SORT_REC, 'S', 'G', 0), cur == ROW_SORT);
    box(0x82, 0x70, FL_EN, cur == ROW_CHECK);

    if (cur == ROW_PICK) StoreDrawParams(0, 1, 0); else StoreDrawParams(3, 0, 0);
    DrawRect(0x53, 0x7f, 0x9b, 0x8c, 1);
    SetText(pick_str, 8, 11, 16);
    StoreDrawParams(3, 0, 0);
}
