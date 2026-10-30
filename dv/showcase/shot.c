/* Headless screenshots of the kernel in SameBoy's core (with the repo's EZ Flash
 * Jr patch, scripts/setup-sameboy.sh): boots it with a Game Boy Color's colors, plays a button
 * script, and writes the frames it asks for as 160x144 PPM files. No window, no
 * screen-recording or accessibility permission. Built and run by
 * dv/showcase/make_screens.py.
 *
 * The kernel is a DMG-mode program, so a Game Boy Color shows it through one
 * fixed compatibility palette: white, #7BFF31 green, #0063C5 blue, black for a
 * cart without a Nintendo licensee code. SameBoy's own CGB boot ROM picks a
 * different one, so this runs the DMG model with exactly that palette, which
 * gives the same pixels a real GBC shows.
 *
 *   shot <dmg_boot.bin> <kernel> <script> <outdir>
 *
 * Script, one command per line ('#' comments):
 *   wait N          run N frames
 *   tap KEY         hold KEY 6 frames, release, run 12 more
 *   hold KEY        press KEY and keep it down
 *   release KEY     let it go
 *   shot NAME       write <outdir>/NAME.ppm from the last frame
 * KEY: UP DOWN LEFT RIGHT A B SELECT START
 * The SD card image comes from SAMEBOY_EZFLASH_JR_IMG, as in the SDL build.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <Core/gb.h>

static uint32_t pixels[160 * 144];

/* darkest first, then the LCD-off color (GB_palette_t order) */
static const GB_palette_t gbc_default = {{{0x00, 0x00, 0x00}, {0x00, 0x63, 0xC5}, {0x7B, 0xFF, 0x31}, {0xFF, 0xFF, 0xFF}, {0xFF, 0xFF, 0xFF}}};

static uint32_t rgb_encode(GB_gameboy_t *gb, uint8_t r, uint8_t g, uint8_t b)
{
    (void)gb;
    return (uint32_t)r << 16 | (uint32_t)g << 8 | b;
}

static void quiet(GB_gameboy_t *gb, const char *s, GB_log_attributes_t a)
{
    (void)gb; (void)s; (void)a;
}

static int key_of(const char *s)
{
    static const char *names[] = {"RIGHT", "LEFT", "UP", "DOWN", "A", "B", "SELECT", "START"};
    for (int i = 0; i < 8; i++) {
        if (strcmp(s, names[i]) == 0) return i;
    }
    fprintf(stderr, "unknown key %s\n", s);
    exit(2);
}

static void frames(GB_gameboy_t *gb, int n)
{
    while (n-- > 0) GB_run_frame(gb);
}

static void save(const char *dir, const char *name)
{
    char path[1024];
    snprintf(path, sizeof(path), "%s/%s.ppm", dir, name);
    FILE *f = fopen(path, "wb");
    if (!f) { perror(path); exit(1); }
    fprintf(f, "P6\n160 144\n255\n");
    for (int i = 0; i < 160 * 144; i++) {
        uint8_t px[3] = {pixels[i] >> 16, pixels[i] >> 8, pixels[i]};
        fwrite(px, 1, 3, f);
    }
    fclose(f);
}

int main(int argc, char **argv)
{
    if (argc != 5) {
        fprintf(stderr, "usage: %s <dmg_boot.bin> <kernel> <script> <outdir>\n", argv[0]);
        return 2;
    }
    GB_gameboy_t *gb = GB_init(GB_alloc(), GB_MODEL_DMG_B);
    if (GB_load_boot_rom(gb, argv[1])) { fprintf(stderr, "no boot ROM %s\n", argv[1]); return 1; }
    GB_set_pixels_output(gb, pixels);
    GB_set_rgb_encode_callback(gb, rgb_encode);
    GB_set_log_callback(gb, quiet);
    GB_set_palette(gb, &gbc_default);
    if (GB_load_rom(gb, argv[2])) { perror(argv[2]); return 1; }

    FILE *s = fopen(argv[3], "r");
    if (!s) { perror(argv[3]); return 1; }
    char line[256], cmd[32], arg[200];
    while (fgets(line, sizeof(line), s)) {
        char *hash = strchr(line, '#');
        if (hash) *hash = 0;
        int n = sscanf(line, "%31s %199s", cmd, arg);
        if (n < 1) continue;
        if (n == 2 && strcmp(cmd, "wait") == 0) frames(gb, atoi(arg));
        else if (n == 2 && strcmp(cmd, "tap") == 0) {
            int k = key_of(arg);
            GB_set_key_state(gb, k, true);  frames(gb, 6);
            GB_set_key_state(gb, k, false); frames(gb, 12);
        }
        else if (n == 2 && strcmp(cmd, "hold") == 0) GB_set_key_state(gb, key_of(arg), true);
        else if (n == 2 && strcmp(cmd, "release") == 0) GB_set_key_state(gb, key_of(arg), false);
        else if (n == 2 && strcmp(cmd, "shot") == 0) save(argv[4], arg);
        else { fprintf(stderr, "bad script line: %s", line); return 2; }
    }
    fclose(s);
    GB_free(gb);
    GB_dealloc(gb);
    return 0;
}
