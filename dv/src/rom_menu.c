/* ezgb-dv: modified copy of kernel/src/rom_menu.c (12px only, a third option
 * to star the game). dv/build.py places it at 04:5a00; the inject.py line below
 * is upstream's.
 *
 * Hold A on a ROM: options menu (docs/rom-menu.md).
 *
 * Bank 4, injected at 04:5a00. MenuDispatchAB_fileOpen (00:145f) began with
 * an inline far call to DrawLoadingBox; it now calls RomMenuHoldStub
 * (00:0597), which far-calls this with a pointer to the browser frame's
 * record-offset slot (the loop's sp+4) and reads E:
 *
 *   0  go on with the stock open: DrawLoadingBox has been drawn here
 *      (FarCallDrawLoadingBox, 00:0483) and the launch path runs as before
 *   1  back to the browser loop (MenuDispatchAB_waitVBlankLoop, 00:16ab);
 *      a closed menu is cleared and sets the loop's redraw code to 1, so
 *      the page is repainted from the sorted records without re-reading the
 *      directory (and the cursor stays where it was)
 *
 * A tap launches when A comes up; holding A for HOLD_FRAMES opens the menu
 * as soon as the hold is reached. A on "Manage saves" runs ManageSaves
 * (save_mgr.c) and redraws the menu when it returns. Pick mode (FL_PICK)
 * and files that are not .gb/.gbc take the stock path straight away. An A that was already down at
 * the browser's previous poll (held on from the press that opened a folder)
 * is ignored until it is let go: RomMenuPadTrack (00:0453) wraps the loop's
 * ReadJoypad and keeps the previous and current reports in HRAM.
 *
 * While the hold is timed nothing reads the pad but the VBlank sampler
 * (VBlankPadLatch), so hPadLive ($fffc) holds the live state once a frame has
 * passed (ReadJoypadLatched also writes it, with the latch folded in).
 *
 * The box is the BACKUPSAVE prompt's (bkprompt.c) made two rows taller,
 * with the ROM's name on the same band, drawn and scrolled by LastRomName
 * (LR_GEO = 1); the menu polls through LastRomTickStub, which runs the
 * marquee. The name is copied to $c4a4 first: the record sits in the pSRAM
 * window, and the open path clears and refills $c4a4 itself afterwards.
 *
 *   8px   box (0,35)-(159,115); title, name, two options, buttons on tile
 *         rows 5, 7, 9, 11, 13; band y 51..67; rule y 99, vertical x 83
 *   12px  box (0,36)-(159,119); rows at y 40, 56, 72, 88, 104 from x 12;
 *         band y 53..69; rule y 101, vertical x 79
 *
 *   python3 tools/inject.py src/rom_menu.c $V 4 5a00 RomMenu \
 *       --pin FarCallDrawString12=05c0 --pin LastRomNameStub=0368 \
 *       --pin LastRomTickStub=0370 --pin FarCallDrawLoadingBox=0483 \
 *       --pin ManageSaves=6d11 --pin DrawString=08b7 --pin DrawRect=27ba --pin StoreDrawParams=2791 \
 *       --pin hUiMode=fffb --apply
 */

typedef unsigned char u8;
typedef unsigned int u16;

/* ezjr custom build: 12px only, and a third option to star the ROM. A star
 * pins it to the top of the list (SORT TOP and A-Z alike) and draws a star
 * icon; the play table lives in pSRAM page $11 (asm/bank5.asm). Toggling
 * re-sorts the directory and puts the cursor on the first entry. */

extern void FarCallDrawString12(const u8 *s, u8 len, u8 col, u8 row);   /* 00:05c0 -> 02:7500 */
extern void LastRomNameStub(const u8 *s);                           /* 00:0368 -> LastRomName */
extern u8 LastRomTickStub(void);                                    /* 00:0370: marquee tick, then ReadJoypad */
extern void FarCallDrawLoadingBox(void);                            /* 00:0483 -> 08:737f */
extern void ManageSaves(u8 page);                                   /* 04:6d11, save_mgr.c */
extern void DrawRect(u8 x0, u8 y0, u8 x1, u8 y1, u8 fill);          /* 00:27ba */
extern void StoreDrawParams(u8 color, u8 colorB, u8 op);            /* 00:2791 */
extern u8 StarQueryStub(void);                                      /* bank-0 stub -> 05 StarQuery */
extern u8 StarToggleStub(void);                                     /* bank-0 stub -> 05 StarToggle */
extern void ResortStub(void);                                       /* bank-0 stub: sort, then mark stars */

#define FL_PICK   (*(volatile u8 *)0xDBFE)
#define LR_GEO    (*(volatile u8 *)0xDB3F)
#define REC_BASE  (*(volatile u16 *)0xC2A0)
#define NAME_BUF  ((u8 *)0xC4A4)
#define HFRAME    (*(volatile u8 *)0xFFFA)
#define PAD_LIVE  (*(volatile u8 *)0xFFFC)
#define PAD_PREV  (*(volatile u8 *)0xFFF5)
#define PAD_CUR   (*(volatile u8 *)0xFFF6)
#define PAD_UP    0x04
#define PAD_DOWN  0x08
#define PAD_A     0x10
#define PAD_B     0x20
#define HOLD_FRAMES 30
#define REDRAW_OFS 0x0e                     /* the loop's sp+$12, from its sp+4 */
#define BASE_OFS   0x0f                     /* sp+$13: first visible entry (u16) */
#define SEL_OFS    0x11                     /* sp+$15: row within the window */

static u8 is_rom(const u8 *s);
static u8 a_held(void);
static void box(void);
static void options(u8 sel, u8 starred);
static void text(const u8 *s, u8 y);
static void frame(void);

u8 RomMenu(u16 far_pad_thunk, u16 far_pad_af, u8 *slot) {
    const u8 *rec;
    u8 i, f, pad, prev, sel, starred;

    (void)far_pad_thunk;
    (void)far_pad_af;
    if (FL_PICK) goto open;
    rec = (const u8 *)(*(u16 *)slot + REC_BASE);
    if (!is_rom(rec)) goto open;
    if (PAD_PREV & PAD_A) {
        while (a_held()) {}
        PAD_CUR = 0;
        return 1;
    }
    f = HFRAME;
    for (;;) {
        if (!a_held()) goto open;
        if ((u8)(HFRAME - f) >= HOLD_FRAMES) break;
    }

    for (i = 0; i < 254 && rec[i]; i++) NAME_BUF[i] = rec[i];
    NAME_BUF[i] = 0;
    starred = StarQueryStub();
    box();
    sel = 0;
    options(sel, starred);
    prev = PAD_A;
    for (;;) {
        f = HFRAME;
        while (HFRAME == f) {}
        pad = LastRomTickStub();
        f = pad & (u8)~prev;
        prev = pad;
        if (f & PAD_UP) {
            sel = sel ? sel - 1 : 2;
            options(sel, starred);
        } else if (f & PAD_DOWN) {
            sel = sel == 2 ? 0 : sel + 1;
            options(sel, starred);
        } else if (f & PAD_B) {
            break;
        } else if (f & PAD_A) {
            if (sel == 0) goto open;
            if (sel == 2) {
                StarToggleStub();
                ResortStub();
                *(u16 *)(slot + BASE_OFS) = 0;
                slot[SEL_OFS] = 0;
                break;
            }
            ManageSaves((u8)((u16)(*(u16 *)(slot + BASE_OFS) + slot[SEL_OFS]) >> 5) + 0x12);
            box();
            options(sel, starred);
            prev = 0xFF;
        }
    }
    StoreDrawParams(0, 0, 0);
    DrawRect(0, 32, 159, 139, 1);
    StoreDrawParams(3, 0, 0);
    slot[REDRAW_OFS] = 1;
    PAD_CUR = 0;
    return 1;

open:
    PAD_CUR = 0;
    FarCallDrawLoadingBox();
    return 0;
}

static u8 is_rom(const u8 *s) {
    const u8 *dot = 0;
    u8 i;

    for (i = 0; i < 254 && s[i]; i++) if (s[i] == '.') dot = s + i;
    if (!dot || (dot[1] | 0x20) != 'g' || (dot[2] | 0x20) != 'b') return 0;
    return dot[3] == 0 || ((dot[3] | 0x20) == 'c' && dot[4] == 0);
}

static u8 a_held(void) {
    u8 f = HFRAME;

    while (HFRAME == f) {}
    return PAD_LIVE & PAD_A;
}

/* box (0,36)-(159,135): title y 40, name band y 53..69, options y 72/88/104,
 * rule y 117, buttons y 120 split at x 79 */
static void box(void) {
    static const u8 title_str[8] = {'O','p','t','i','o','n','s',0};
    static const u8 back_str[8]  = {'[','B',']','b','a','c','k',0};
    static const u8 ok_str[6]    = {'[','A',']','o','k',0};
    u8 buf[6];
    u8 i;

    StoreDrawParams(0, 0, 0);
    DrawRect(0, 32, 159, 139, 1);
    StoreDrawParams(3, 0, 0);
    DrawRect(0, 36, 159, 135, 1);
    text(title_str, 40);
    text(back_str, 120);
    for (i = 0; i < 6; i++) buf[i] = ok_str[i];
    FarCallDrawString12(buf, 0, 86, 120);
    frame();
    StoreDrawParams(3, 3, 0);
    DrawRect(0, 53, 159, 69, 1);
    LR_GEO = 1;
    LastRomNameStub(NAME_BUF);
}

static void options(u8 sel, u8 starred) {
    static const u8 start_str[8]  = {' ',' ','S','t','a','r','t',0};
    static const u8 saves_str[15] = {' ',' ','M','a','n','a','g','e',' ','s','a','v','e','s',0};
    static const u8 star_str[9]   = {' ',' ','S','t','a','r',' ',' ',0};
    static const u8 unstar_str[9] = {' ',' ','U','n','s','t','a','r',0};
    u8 buf[15];
    u8 i;
    const u8 *s;

    StoreDrawParams(3, 0, 0);
    for (i = 0; i < 8; i++) buf[i] = start_str[i];
    if (sel == 0) buf[0] = '>';
    text(buf, 72);
    for (i = 0; i < 15; i++) buf[i] = saves_str[i];
    if (sel == 1) buf[0] = '>';
    text(buf, 88);
    s = starred ? unstar_str : star_str;
    for (i = 0; i < 9; i++) buf[i] = s[i];
    if (sel == 2) buf[0] = '>';
    text(buf, 104);
    frame();
}

static void text(const u8 *s, u8 y) {
    u8 buf[24];
    u8 i;

    for (i = 0; i < 23 && s[i]; i++) buf[i] = s[i];
    buf[i] = 0;
    FarCallDrawString12(buf, 0, 1, y);
}

static void frame(void) {
    StoreDrawParams(3, 0, 0);
    DrawRect(0, 36, 159, 135, 0);
    StoreDrawParams(3, 3, 0);
    DrawRect(0, 117, 159, 117, 1);
    DrawRect(79, 117, 79, 135, 1);
    StoreDrawParams(3, 0, 0);
}
