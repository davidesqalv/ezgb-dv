/* ezgb-dv: modified copy of kernel/src/settext.c (12px only, a 2 px left
 * margin, and the rows flcfg.c's copy rearranged). dv/build.py places it at
 * 04:6400; the inject.py line below is upstream's.
 *
 * SET pane text in the UI mode's font (docs/set-pane12.md).
 *
 * Bank 4, injected at 04:6400. Every `call DrawString` of the stock SET
 * screen (DrawTimeAutosaveScreen, 04:46f4..5162: TIME:, the SET / SAV button
 * text, AUTO SAVE:, the date and time fields and their separators, in all of
 * its draw and time-edit paths) calls this instead, with the same
 * (s, len, col, row) frame; flcfg.c's rows go through it too.
 *
 * The pane keeps its rows (tile rows 2, 4, .. 14, 16 px apart), and a 12px
 * row fits that pitch, so y is 8 * row. What changes is x: a field's
 * (col, row) picks its start x and the x where it ends, and the text is
 * drawn by DrawString12 with hClip12 set to that end, so a field repaints
 * exactly its own span (in the current ink and paper: the time-edit
 * highlight is the field's rectangle) and never the field to its right.
 * Text that started at x 0 starts at PAD; the date row, which filled all
 * 160 px, makes the room from the blank between the date and the time.
 *
 *   row 2   col 0 "TIME:"   2..120     col 16 SET/SAV  127..155 (in its box)
 *   row 4   the date and time: digits 9 px, '/' 8, ':' 6, the blank 4;
 *           col -> x through date_x[], a field of len ends at date_x[col+len]
 *   row 6   col 0 "RTC:" 2..44   col 6 "SD" 44..66   col 11 "NO SD" 86..130
 *   row 8, 10, 12, 14   labels 2..128 (the checkbox is at x 130): AUTO
 *           SAVE, DAILY BACKUP, SORT A-Z, FAST LAUNCH
 *   row 16  col 0 the fast-launch name 2..80   col 11 "PICK ROM" 88..155
 *
 * DrawString12 takes a col >= 2 as a pixel x (0 is x 0, 1 the name field
 * at x 12), so PAD can't be 1.
 *
 * The renderer runs in bank 2, so the string is copied to the stack first.
 *
 *   python3 tools/inject.py src/settext.c $V 4 6400 SetText \
 *       --pin FarCallDrawString12=05c0 --pin DrawString=08b7 \
 *       --pin hUiMode=fffb --pin hClip12=fff9 --replace --apply
 */

typedef unsigned char u8;

extern void FarCallDrawString12(const u8 *s, u8 len, u8 col, u8 row);   /* 00:05c0 -> 02:7500 */
extern volatile u8 hClip12;                                         /* $fff9: DrawString12's right edge */

#define PAD 2

void SetText(const u8 *s, u8 len, u8 col, u8 row) {
    /* 2026/09/30 17:40:14: x of each of the 19 columns, and the end */
    static const u8 date_x[20] = {PAD, 11, 20, 29, 38, 46, 55, 64, 72, 81,
                                  90, 94, 103, 112, 118, 127, 136, 142, 151, 160};
    u8 buf[24];
    u8 i, x, end;

    x = PAD;
    end = 128;
    switch (row) {
    case 2:
        if (col) { x = 127; end = 155; } else { end = 120; }
        break;
    case 4:
        x = date_x[col];
        end = date_x[(u8)(col + len)];
        break;
    case 6:
        if (col == 0) { end = 44; }
        else if (col == 6) { x = 44; end = 66; }
        else { x = 86; end = 130; }
        break;
    case 16:
        if (col) { x = 88; end = 155; } else { end = 80; }
        break;
    }
    if (len == 0 || len > 23) len = 23;
    for (i = 0; i < len && s[i]; i++) buf[i] = s[i];
    buf[i] = 0;
    hClip12 = end;
    /* row * 8 + 2: DrawString12 takes a row >= 18 as a pixel y and rounds
     * it down to a multiple of 4, which is how y 16 (row 2) is reachable */
    FarCallDrawString12(buf, 0, x, (u8)((u8)(row << 3) + 2));
    hClip12 = 0;
}
