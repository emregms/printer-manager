/*
 * clp300-raster: Ghostscript'in renkli (P6) ya da gri (P5) raster çıktısını
 * bir CLP-300 renk tablosu ve yarım ton matrisleriyle foo2qpdl'in beklediği
 * 1 bitlik rastere çevirir (fotoğraf modu).
 *
 * Veriler bir klasördeki düz metin dosyalarından okunur: Samsung'un Mac
 * sürücüsünün kurduğu dosyalar (/Library/Printers/Samsung/CLP-300; repoda
 * yoktur) ya da Scripts/make-colour-tables.py'nin baştan ürettiği, uygulamayla
 * gelen kendi verimiz (PrinterManager/Resources/ColorTables/CLP-300):
 *   RGB2CMYK_<çözünürlük>1  "17 17 17 4" başlığı, sonra R (en yavaş), G, B
 *                           sırasıyla 17x17x17 düğümde C M Y K. Değerler
 *                           ters: 255 toner yok, 0 tam toner.
 *   <Renk>HT_<çözünürlük>   genişlik, yükseklik, sonra satır satır eşikler
 *                           (1-255). Değer eşikten küçükse nokta basılır.
 * Biçim ve kural Samsung'un dosyalarından çıkarıldı: eşik dağılımı yalnızca
 * "değer < eşik" kuralıyla açık tonları açık bırakır (%50 girişte ~%41
 * kaplama); yani matrisler yazıcının nokta kazancını zaten dengeler. Kendi
 * verimiz de aynı kurala göre üretilir (%50 girişte %40 kaplama).
 *
 *   clp300-raster <veri-klasörü> <600x600|1200x600|1200x1200>  <P6|P5  >bitcmyk|P4
 *
 * P6 girişinden bitcmyk (bayt başına 2 piksel: CMYK CMYK) üretir, foo2qpdl
 * -A/-B olmadan okur. P5 girişinden GrayHT ile PBM (P4) üretir. Art arda
 * gelen sayfaların hepsi işlenir; sayfa satır satır akar, bellekte tutulmaz.
 *
 * Çıkış kodu: 0 başarı, 2 kullanım, 3 veri dosyası okunamadı, 4 giriş hatalı.
 */

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define NODES 17

typedef struct {
    int width;
    int height;
    uint8_t *values;
} Screen;

static uint8_t lut[NODES][NODES][NODES][4];
/* 0-255 değerin düğümü (0-15) ve iki düğüm arasındaki konumu (0-256) */
static int nodeIndex[256];
static int nodeFrac[256];

/* Dosyadaki tüm tamsayıları okur; okunan sayı adedini, hata olursa -1 döndürür */
static long read_numbers(const char *path, int **numbers)
{
    FILE *fp = fopen(path, "rb");
    if (!fp) return -1;
    fseek(fp, 0, SEEK_END);
    long size = ftell(fp);
    fseek(fp, 0, SEEK_SET);
    char *text = malloc(size + 1);
    if (!text || fread(text, 1, size, fp) != (size_t)size) {
        fclose(fp);
        free(text);
        return -1;
    }
    fclose(fp);
    text[size] = 0;

    long count = 0, capacity = 4096;
    int *values = malloc(capacity * sizeof(int));
    char *p = text, *end;
    for (;;) {
        long value = strtol(p, &end, 10);
        if (end == p) {
            if (*p == 0) break;
            ++p;  /* boşluk, sekme, CRLF */
            continue;
        }
        if (count == capacity) {
            capacity *= 2;
            values = realloc(values, capacity * sizeof(int));
        }
        values[count++] = (int)value;
        p = end;
    }
    free(text);
    *numbers = values;
    return count;
}

static int load_lut(const char *dir, const char *suffix)
{
    char path[1024];
    int *numbers;
    snprintf(path, sizeof(path), "%s/RGB2CMYK_%s1", dir, suffix);
    long count = read_numbers(path, &numbers);
    if (count != 4 + NODES * NODES * NODES * 4 || numbers[0] != NODES || numbers[1] != NODES
        || numbers[2] != NODES || numbers[3] != 4) {
        fprintf(stderr, "clp300-raster: %s okunamadı ya da biçimi beklenmedik\n", path);
        return -1;
    }
    uint8_t *out = &lut[0][0][0][0];
    for (long i = 4; i < count; ++i) {
        int value = numbers[i];
        out[i - 4] = (uint8_t)(value < 0 ? 0 : value > 255 ? 255 : value);
    }
    free(numbers);

    for (int v = 0; v < 256; ++v) {
        int scaled = v * (NODES - 1) * 256 / 255;  /* 0 .. 16*256 */
        int index = scaled >> 8;
        if (index > NODES - 2) index = NODES - 2;
        nodeIndex[v] = index;
        nodeFrac[v] = scaled - (index << 8);
    }
    return 0;
}

static int load_screen(const char *dir, const char *color, const char *suffix, Screen *screen)
{
    char path[1024];
    int *numbers;
    snprintf(path, sizeof(path), "%s/%sHT_%s", dir, color, suffix);
    long count = read_numbers(path, &numbers);
    if (count < 3 || numbers[0] <= 0 || numbers[1] <= 0
        || count != 2 + (long)numbers[0] * numbers[1]) {
        fprintf(stderr, "clp300-raster: %s okunamadı ya da biçimi beklenmedik\n", path);
        return -1;
    }
    screen->width = numbers[0];
    screen->height = numbers[1];
    screen->values = malloc((size_t)screen->width * screen->height);
    for (long i = 2; i < count; ++i) {
        int value = numbers[i];
        screen->values[i - 2] = (uint8_t)(value < 0 ? 0 : value > 255 ? 255 : value);
    }
    free(numbers);
    return 0;
}

/* 17x17x17 tablodan dört yüzlü (tetrahedral) ara değerleme */
static void convert(int r, int g, int b, int out[4])
{
    int ri = nodeIndex[r], gi = nodeIndex[g], bi = nodeIndex[b];
    int fr = nodeFrac[r], fg = nodeFrac[g], fb = nodeFrac[b];
    const uint8_t *c000 = lut[ri][gi][bi];
    const uint8_t *c111 = lut[ri + 1][gi + 1][bi + 1];
    const uint8_t *p1, *p2;  /* köşegen boyunca ara köşeler */
    int f1, f2, f3;

    if (fr >= fg) {
        if (fg >= fb) {         /* r >= g >= b */
            p1 = lut[ri + 1][gi][bi]; p2 = lut[ri + 1][gi + 1][bi]; f1 = fr; f2 = fg; f3 = fb;
        } else if (fr >= fb) {  /* r >= b > g */
            p1 = lut[ri + 1][gi][bi]; p2 = lut[ri + 1][gi][bi + 1]; f1 = fr; f2 = fb; f3 = fg;
        } else {                /* b > r >= g */
            p1 = lut[ri][gi][bi + 1]; p2 = lut[ri + 1][gi][bi + 1]; f1 = fb; f2 = fr; f3 = fg;
        }
    } else {
        if (fb >= fg) {         /* b >= g > r */
            p1 = lut[ri][gi][bi + 1]; p2 = lut[ri][gi + 1][bi + 1]; f1 = fb; f2 = fg; f3 = fr;
        } else if (fb >= fr) {  /* g > b >= r */
            p1 = lut[ri][gi + 1][bi]; p2 = lut[ri][gi + 1][bi + 1]; f1 = fg; f2 = fb; f3 = fr;
        } else {                /* g > r > b */
            p1 = lut[ri][gi + 1][bi]; p2 = lut[ri + 1][gi + 1][bi]; f1 = fg; f2 = fr; f3 = fb;
        }
    }
    for (int i = 0; i < 4; ++i) {
        int value = (c000[i] << 8) + f1 * (p1[i] - c000[i]) + f2 * (p2[i] - p1[i])
            + f3 * (c111[i] - p2[i]);
        value = (value + 128) >> 8;
        out[i] = value < 0 ? 0 : value > 255 ? 255 : value;
    }
}

/* PNM başlığından bir sayı okur (boşluk ve # yorumları atlanır) */
static int read_header_number(FILE *in, int *value)
{
    int c = getc(in);
    for (;;) {
        if (c == '#') {
            while (c != '\n' && c != EOF) c = getc(in);
        } else if (c == ' ' || c == '\t' || c == '\r' || c == '\n') {
            c = getc(in);
        } else {
            break;
        }
    }
    if (c < '0' || c > '9') return -1;
    *value = 0;
    while (c >= '0' && c <= '9') {
        *value = *value * 10 + (c - '0');
        c = getc(in);
    }
    /* Sayıdan sonraki tek boşluk karakteri başlığa aittir */
    return 0;
}

static int color_page(FILE *in, FILE *out, int width, int height, Screen screens[4])
{
    uint8_t *row = malloc((size_t)width * 3);
    uint8_t *packed = malloc((size_t)(width + 1) / 2);
    int lastR = -1, lastG = -1, lastB = -1, bits;
    int value[4] = { 255, 255, 255, 255 };

    for (int y = 0; y < height; ++y) {
        if (fread(row, 3, width, in) != (size_t)width) {
            free(row);
            free(packed);
            return -1;
        }
        const uint8_t *thresholds[4];
        int column[4];
        for (int i = 0; i < 4; ++i) {
            thresholds[i] = screens[i].values + (size_t)(y % screens[i].height) * screens[i].width;
            column[i] = 0;
        }
        memset(packed, 0, (width + 1) / 2);

        for (int x = 0; x < width; ++x) {
            int r = row[3 * x], g = row[3 * x + 1], b = row[3 * x + 2];
            if (r != lastR || g != lastG || b != lastB) {
                convert(r, g, b, value);
                lastR = r; lastG = g; lastB = b;
            }
            bits = 0;
            if (value[0] < thresholds[0][column[0]]) bits |= 8;
            if (value[1] < thresholds[1][column[1]]) bits |= 4;
            if (value[2] < thresholds[2][column[2]]) bits |= 2;
            if (value[3] < thresholds[3][column[3]]) bits |= 1;
            packed[x >> 1] |= (x & 1) ? bits : bits << 4;
            for (int i = 0; i < 4; ++i) {
                if (++column[i] == screens[i].width) column[i] = 0;
            }
        }
        fwrite(packed, 1, (width + 1) / 2, out);
    }
    free(row);
    free(packed);
    return 0;
}

static int gray_page(FILE *in, FILE *out, int width, int height, Screen *screen)
{
    uint8_t *row = malloc(width);
    int rowBytes = (width + 7) / 8;
    uint8_t *packed = malloc(rowBytes);

    fprintf(out, "P4\n%d %d\n", width, height);
    for (int y = 0; y < height; ++y) {
        if (fread(row, 1, width, in) != (size_t)width) {
            free(row);
            free(packed);
            return -1;
        }
        const uint8_t *thresholds = screen->values + (size_t)(y % screen->height) * screen->width;
        memset(packed, 0, rowBytes);
        for (int x = 0, column = 0; x < width; ++x) {
            if (row[x] < thresholds[column]) packed[x >> 3] |= 0x80 >> (x & 7);
            if (++column == screen->width) column = 0;
        }
        fwrite(packed, 1, rowBytes, out);
    }
    free(row);
    free(packed);
    return 0;
}

int main(int argc, char **argv)
{
    if (argc != 3) {
        fprintf(stderr, "kullanım: clp300-raster <veri-klasörü> <600x600|1200x600|1200x1200>"
                " <P6|P5 >bitcmyk|P4\n");
        return 2;
    }
    const char *dir = argv[1];
    const char *suffix;
    if (strcmp(argv[2], "600x600") == 0) {
        suffix = "600";
    } else if (strcmp(argv[2], "1200x600") == 0) {
        suffix = "1200600";
    } else if (strcmp(argv[2], "1200x1200") == 0) {
        suffix = "12001200";
    } else {
        fprintf(stderr, "clp300-raster: bilinmeyen çözünürlük %s\n", argv[2]);
        return 2;
    }
    /* Tablonun dosya adı 600 dpi'de de iki eksenli: RGB2CMYK_6006001 */
    const char *lutSuffix = strcmp(suffix, "600") == 0 ? "600600" : suffix;

    static char inBuffer[1 << 20], outBuffer[1 << 20];
    setvbuf(stdin, inBuffer, _IOFBF, sizeof(inBuffer));
    setvbuf(stdout, outBuffer, _IOFBF, sizeof(outBuffer));

    Screen screens[4], gray;
    int loaded = 0;  /* renk verisi ilk renkli sayfada yüklenir */
    int grayLoaded = 0;
    const char *colors[4] = { "Cyan", "Magenta", "Yellow", "Black" };

    for (int page = 0;; ++page) {
        int c = getc(stdin);
        while (c == ' ' || c == '\t' || c == '\r' || c == '\n') c = getc(stdin);
        if (c == EOF) return page > 0 ? 0 : 4;
        int kind = getc(stdin);
        int width, height, maxValue;
        if (c != 'P' || (kind != '6' && kind != '5') || read_header_number(stdin, &width)
            || read_header_number(stdin, &height) || read_header_number(stdin, &maxValue)
            || maxValue != 255 || width <= 0 || height <= 0) {
            fprintf(stderr, "clp300-raster: sayfa %d: P6/P5 (8 bit) bekleniyordu\n", page + 1);
            return 4;
        }

        int failed;
        if (kind == '6') {
            if (!loaded) {
                if (load_lut(dir, lutSuffix)) return 3;
                for (int i = 0; i < 4; ++i) {
                    if (load_screen(dir, colors[i], suffix, &screens[i])) return 3;
                }
                loaded = 1;
            }
            failed = color_page(stdin, stdout, width, height, screens);
        } else {
            if (!grayLoaded) {
                if (load_screen(dir, "Gray", suffix, &gray)) return 3;
                grayLoaded = 1;
            }
            failed = gray_page(stdin, stdout, width, height, &gray);
        }
        if (failed) {
            fprintf(stderr, "clp300-raster: sayfa %d eksik\n", page + 1);
            return 4;
        }
        fflush(stdout);
    }
}
