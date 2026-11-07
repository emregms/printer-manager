#!/usr/bin/env python3
"""Fotoğraf modu için PrinterManager'ın kendi CLP-300 renk verisini üretir.

    python3 Scripts/make-colour-tables.py [çıktı-klasörü] [--gain-at-40 0.50]

Varsayılan çıktı PrinterManager/Resources/ColorTables/CLP-300; uygulama bu klasörü
paketin içine koyar (Contents/Resources/ColorTables/CLP-300). Dosya biçimi
Driver/clp300-raster.c'nin başındaki açıklamadaki gibidir:

  RGB2CMYK_<çözünürlük>1   17x17x17 düğümde RGB → CMYK (ters: 255 toner yok, 0 tam)
  <Renk>HT_<çözünürlük>    yarım ton eşikleri (1-255); değer < eşik ise nokta basılır

Veri baştan, yalnızca aşağıdaki varsayımlardan hesaplanır; Samsung'un dosyaları
okunmaz, kopyalanmaz ve hiçbir değeri girdi olarak kullanılmaz. Aynı betik her
çalıştığında bayt bayt aynı dosyaları üretir (rastgelelik yok). Gerekenler:
Python 3 ve numpy.

Yöntem kısaca:
  1. Yazıcı modeli (Neugebauer): kağıdın, tonerlerin ve üst üste binmiş hâllerinin
     tam kaplama rengi (tipik renkli lazer, aşağıda PRIMARY_LAB) ve rastgele üst
     üste binen noktalar (Demichel); renkler XYZ'de alan oranıyla karışır.
     Kaplama, nokta kazancı dengelendikten sonraki etkin kaplamadır.
  2. Hedef renk: sRGB, kağıt beyazı beyaz kabul edilerek (siyah nokta yazıcının en
     koyu siyahına ölçeklenir) Oklab'a çevrilir. Oklab'da mavi tonlar morlaşmaz.
  3. Gamut eşleme: her ton açısında sRGB'nin en doygun noktası (ana ve ara
     renkler) yazıcının en doygun noktasına taşınır (saf sRGB rengi tam toner);
     doygunluk bir dizden sonra yumuşakça sıkıştırılır, az doygun renkler (gri,
     ten, gökyüzü) neredeyse hiç değişmez. Koyu doygun renkler (lacivert) griye
     dönmesin diye açıklık ve doygunluk birlikte kırpılır; kalan taşmalar ton
     açısı korunarak kırpılır.
  4. Ayrıştırma (düşük GCR): K grilerde yalnızca koyu tonlarda, doygun renklerde
     o tonun en doygun noktasından koyu tonlarda başlar; orta griler C+M+Y ile
     basılır. Toplam toner %240 ile sınırlı; sınır yüzünden ulaşılamayan koyu
     tonlarda K artar ve komşu düğümlere yumuşatılır. C, M, Y modeli tersine
     çözülerek bulunur.
  5. Yarım ton: her renk için kümelenmiş nokta (Öklid noktası), ~95 lpi, klasik
     açıların tam sayı ızgaraya oturan hâlleri (C 18,4°, M 71,6°, Y 0°, K 45°).
     Hücreler süper hücrelerde sırayla büyür (en az ~240 gri düzeyi); 1200x600'de
     pikseller dikdörtgen olduğundan noktalar fiziksel olarak yuvarlak hesaplanır.
  6. Nokta kazancı: bu yazıcıda %50 giriş yaklaşık %40 kaplama ister. Kazanç
     kazanç(d) = d + k·d·(1-d) ile modellenir (k, kazanç(0,40) = 0,50 olacak
     şekilde) ve eşiklere tersi işlenir; tablo etkin kaplamayla hesaplanır.
  7. GrayHT (siyah-beyaz fotoğraf, tablosuz yol): siyah ekranla aynı nokta düzeni;
     gri değerden K kaplamasına giden ton eğrisi eşiklerin içindedir.
"""
import argparse
import math
import os

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_OUTPUT = os.path.join(ROOT, "PrinterManager", "Resources", "ColorTables", "CLP-300")

# MARK: - Varsayımlar

# Neugebauer ana renkleri: kağıt ve tonerlerin tek başına ve üst üste tam kaplama
# rengi, CIELAB (D65, kağıt beyazına göre). Ölçüm değil; düz kağıtta renkli lazer
# için tipik, yuvarlak değerler.
PRIMARY_LAB = {
    "": (100.0, 0.0, 0.0),
    "C": (55.0, -37.0, -50.0),
    "M": (48.0, 74.0, -4.0),
    "Y": (88.0, -6.0, 90.0),
    "MY": (47.0, 66.0, 46.0),
    "CY": (50.0, -62.0, 26.0),
    "CM": (25.0, 22.0, -48.0),
    "CMY": (25.0, 2.0, 0.0),
    "K": (21.0, 0.5, 1.5),
}
K_OVER = 0.28              # K'nın altındaki renk siyahı az koyulaştırır (K+C+M+Y ≈ L* 12)
INK_LIMIT = 2.40           # en fazla toplam toner (C+M+Y+K, 1 = tek renk tam kaplama)
DOT_GAIN_AT_40 = 0.50      # %40 sayısal kaplama kağıtta %50 görünür
K_START = 0.62             # K bu Oklab açıklığının altında başlar (≈ L* 56, sRGB gri ~130)
K_POWER = 1.3              # K'nın en koyuya doğru artış eğrisi
CHROMA_KNEE = 0.75         # yazıcının en doygun noktasının bu oranına kadar doygunluk korunur
NODES = 17

# Ekran hücreleri, fiziksel birimde (1/1200 inç); dik kenar bundan 90° döndürülür.
# ~95 lpi. C ve M, 15°/75° yerine PostScript'in düşük çözünürlüklü cihazlar için
# kullandığı rasyonel tanjantlı açılarda (tan 1/3): desen küçük bir karoda tekrarlar,
# yazıcıya giden JBIG verisi %25 kadar küçülür (1200x600'de tam sayfa fotoğraf < 8 MB).
SCREENS = {
    "Cyan": (12.0, 4.0),     # 18,43°, 94,9 lpi
    "Magenta": (4.0, 12.0),  # 71,57°, 94,9 lpi
    "Yellow": (12.0, 0.0),   # 0°, 100 lpi
    "Black": (9.0, 9.0),     # 45°, 94,3 lpi
}
RESOLUTIONS = {  # dosya adı eki: (yatay dpi, dikey dpi)
    "600": (600, 600),
    "1200600": (1200, 600),
    "12001200": (1200, 1200),
}
LUT_NAMES = {"600": "RGB2CMYK_6006001", "1200600": "RGB2CMYK_12006001", "12001200": "RGB2CMYK_120012001"}

# MARK: - Renk uzayları (hepsi XYZ D65 üzerinden, beyaz Y = 1)

M_XYZ = np.array([[0.4124564, 0.3575761, 0.1804375],
                  [0.2126729, 0.7151522, 0.0721750],
                  [0.0193339, 0.1191920, 0.9503041]])
WHITE = M_XYZ.sum(axis=1)
M_LMS = np.array([[0.8189330101, 0.3618667424, -0.1288597137],
                  [0.0329845436, 0.9293118715, 0.0361456387],
                  [0.0482003018, 0.2643662691, 0.6338517070]])
M_OKLAB = np.array([[0.2104542553, 0.7936177850, -0.0040720468],
                    [1.9779984951, -2.4285922050, 0.4505937099],
                    [0.0259040371, 0.7827717662, -0.8086757660]])


def srgb_decode(v):
    v = np.asarray(v, dtype=float)
    return np.where(v <= 0.04045, v / 12.92, ((v + 0.055) / 1.055) ** 2.4)


def srgb_encode(v):
    v = np.clip(np.asarray(v, dtype=float), 0.0, 1.0)
    return np.where(v <= 0.0031308, v * 12.92, 1.055 * v ** (1 / 2.4) - 0.055)


def srgb_xyz(rgb_encoded):
    return srgb_decode(rgb_encoded) @ M_XYZ.T


def oklab(xyz):
    return np.cbrt(xyz @ M_LMS.T) @ M_OKLAB.T


def cielab(xyz):
    f = xyz / WHITE
    f = np.where(f > (6 / 29) ** 3, np.cbrt(f), f / (3 * (6 / 29) ** 2) + 4 / 29)
    return np.stack([116 * f[..., 1] - 16, 500 * (f[..., 0] - f[..., 1]), 200 * (f[..., 1] - f[..., 2])], axis=-1)


def cielab_xyz(lab):
    L, a, b = lab
    fy = (L + 16) / 116
    f = np.array([fy + a / 500, fy, fy - b / 200])
    return np.where(f > 6 / 29, f ** 3, 3 * (6 / 29) ** 2 * (f - 4 / 29)) * WHITE


def lch(lab):
    return lab[..., 0], np.hypot(lab[..., 1], lab[..., 2]), np.arctan2(lab[..., 2], lab[..., 1])


# MARK: - Yazıcı modeli

# 16 Neugebauer rengi (C, M, Y, K bitleri) ve XYZ değerleri
COMBOS = np.array([[(i >> 3) & 1, (i >> 2) & 1, (i >> 1) & 1, i & 1] for i in range(16)], dtype=bool)


def _primary(bits):
    name = "".join(c for c, on in zip("CMY", bits[:3]) if on)
    xyz = cielab_xyz(PRIMARY_LAB[name])
    if bits[3]:
        xyz = cielab_xyz(PRIMARY_LAB["K"]) * (xyz / WHITE) ** K_OVER
    return xyz


PRIMARIES = np.array([_primary(bits) for bits in COMBOS])


def printed(cmyk):
    """Etkin kaplama (..., 4) → kağıttaki XYZ (Demichel ağırlıklarıyla Neugebauer)"""
    a = cmyk[..., None, :]
    weights = np.prod(np.where(COMBOS, a, 1.0 - a), axis=-1)
    return weights @ PRIMARIES


def gain(d, at_40=DOT_GAIN_AT_40):
    """Sayısal kaplama → kağıtta görünen kaplama (at_40: %40 sayısal kaplamanın görünen hâli)"""
    k = (at_40 - 0.40) / (0.40 * 0.60)
    return d + k * d * (1.0 - d)


def project(x, limit):
    """[0,1] kutusuna ve toplam ≤ limit'e izdüşüm (satır satır)"""
    y = np.clip(x, 0.0, 1.0)
    over = y.sum(axis=-1) > limit
    if np.any(over):
        xs, ls = x[over], limit[over]
        lo, hi = np.zeros(len(xs)), xs.max(axis=-1)
        for _ in range(60):
            mid = (lo + hi) / 2
            above = np.clip(xs - mid[:, None], 0.0, 1.0).sum(axis=-1) > ls
            lo, hi = np.where(above, mid, lo), np.where(above, hi, mid)
        y[over] = np.clip(xs - hi[:, None], 0.0, 1.0)
    return y


def residual(cmy, k, target, weights):
    """Ağırlıklı Oklab farkı: açıklık, hedef yönünde doygunluk ve ton açısı. Koyu
    tonlarda açıklığın ağırlığı azalır: gölgede renk kayması küçük açıklık farkından
    çok daha görünür (koyu yeşil morlaşmasın)."""
    d = oklab(printed(np.concatenate([cmy, k[:, None]], axis=-1))) - target
    L, c, h = lch(target)
    dark = np.clip((L - 0.30) / 0.25, 0.0, 1.0)
    d[:, 0] *= 0.3 + 0.7 * dark * dark * (3 - 2 * dark)
    chromatic = c > 1e-3
    u = np.stack([np.where(chromatic, np.cos(h), 1.0), np.where(chromatic, np.sin(h), 0.0)], axis=-1)
    radial = d[:, 1] * u[:, 0] + d[:, 2] * u[:, 1]
    tangential = -d[:, 1] * u[:, 1] + d[:, 2] * u[:, 0]
    wl, wc, wh = weights
    return np.stack([wl * d[:, 0], np.where(chromatic, wc, wh) * radial, wh * tangential], axis=-1)


def solve_cmy(target, k, start, weights=(2.0, 0.6, 3.0)):
    """K sabitken hedefe en yakın C, M, Y. Sönümlü Gauss-Newton; toner sınırına izdüşüm
    adımı bozarsa izdüşümlü eğim adımı. Hatayı azaltan ilk adım alınır (düğüm düğüm)."""
    limit = INK_LIMIT - k
    x = project(start.copy(), limit)
    r = residual(x, k, target, weights)
    err = (r ** 2).sum(axis=-1)
    active = np.ones(len(x), dtype=bool)
    for _ in range(150):
        idx = np.flatnonzero(active)
        if len(idx) == 0:
            break
        xs, ks, ts, rs, ls = x[idx], k[idx], target[idx], r[idx], limit[idx]
        jac = np.empty(xs.shape + (3,))
        for j in range(3):
            step = np.zeros(3)
            step[j] = 1e-5
            jac[:, :, j] = (residual(xs + step, ks, ts, weights) - residual(xs - step, ks, ts, weights)) / 2e-5
        jt = np.swapaxes(jac, 1, 2)
        jtj = jt @ jac
        grad = (jt @ rs[:, :, None])[:, :, 0]
        newton = np.linalg.solve(jtj + 1e-7 * np.eye(3), grad[:, :, None])[:, :, 0]
        steepest = grad / np.trace(jtj, axis1=1, axis2=2)[:, None].clip(1e-12) * 4
        best_x, best_r, best_e = xs.copy(), rs.copy(), err[idx].copy()
        moved = np.zeros(len(idx), dtype=bool)
        for direction, tries in ((newton, 12), (steepest, 16)):
            for i in range(tries):
                trial = project(xs - direction / 2 ** i, ls)
                tr = residual(trial, ks, ts, weights)
                te = (tr ** 2).sum(axis=-1)
                better = (te < best_e - 1e-16) & ~moved
                best_x[better], best_r[better], best_e[better] = trial[better], tr[better], te[better]
                moved |= better
        change = np.abs(best_x - xs).max(axis=-1)
        x[idx], r[idx], err[idx] = best_x, best_r, best_e
        active[idx] = moved & (change > 1e-9)
    return x, np.sqrt((r ** 2).sum(axis=-1))


def separate(target, k_goal, start):
    """Düşük GCR: K önce k_goal; hedef toner sınırı yüzünden ulaşılamıyorsa hedefe en
    yakın sonucu veren en küçük K'ya çıkar (K'da ızgara, sonra ikiye bölme)."""
    k = k_goal.copy()
    cmy, err = solve_cmy(target, k, start)
    # K yalnızca koyulaştırır: açık renklerdeki gamut taşmasında aranmaz
    hard = np.flatnonzero((err > 0.004) & (target[:, 0] < K_START))
    if len(hard):
        t, kg, s0 = target[hard], k_goal[hard], cmy[hard]
        grid = np.linspace(0.0, 1.0, 11)
        tries = [solve_cmy(t, np.maximum(kg, g), s0) for g in grid]
        errs = np.array([e for _, e in tries])
        enough = errs <= errs.min(axis=0) + 0.002
        first = np.argmax(enough, axis=0)
        hi = np.maximum(kg, grid[first])
        lo = np.where(first > 0, np.maximum(kg, grid[np.maximum(first - 1, 0)]), hi)
        goal = errs.min(axis=0) + 0.002
        for _ in range(8):
            mid = (lo + hi) / 2
            _, e = solve_cmy(t, mid, s0)
            lo, hi = np.where(e <= goal, lo, mid), np.where(e <= goal, mid, hi)
        k[hard] = hi
        # Toner sınırının zorladığı fazladan K komşu düğümlere yumuşatılır: koyu geçişlerde
        # K ile C+M+Y birden yer değiştirmesin. Sonra C, M, Y bu K ile yeniden çözülür.
        extra = (k - k_goal).reshape(NODES, NODES, NODES)
        for axis in range(3):
            padded = np.concatenate([extra.take([0], axis), extra, extra.take([-1], axis)], axis=axis)
            extra = (padded.take(range(0, NODES), axis) + 2 * padded.take(range(1, NODES + 1), axis)
                     + padded.take(range(2, NODES + 2), axis)) / 4
        k = np.clip(k_goal + extra.ravel(), 0.0, 1.0)
        cmy, err = solve_cmy(target, k, cmy)
    return np.concatenate([cmy, k[:, None]], axis=-1), err


# MARK: - Gamut eşleme

def hue_table(points):
    """Doygunluk sınırı üzerindeki noktalar → ton açısına göre sıralı (h, L, C) tablosu"""
    L, C, h = lch(points)
    order = np.argsort(h)
    h, L, C = h[order], L[order], C[order]
    # Ton açısı dairesel: iki uca birer tur ekle
    return np.concatenate([h - 2 * np.pi, h, h + 2 * np.pi]), np.tile(L, 3), np.tile(C, 3)


def corner_path(corners, steps=256):
    t = np.linspace(0.0, 1.0, steps, endpoint=False)[:, None]
    return np.concatenate([a + (b - a) * t for a, b in zip(corners, corners[1:] + corners[:1])])


class Gamut:
    """sRGB'den yazıcı hedefine: siyah nokta, ton açısı, en doygun nokta ve doygunluk eşleme"""

    def __init__(self, black_y):
        self.black_y = black_y
        self.black_l = float(oklab(self.target_xyz(np.zeros(3)))[0])
        srgb_corners = [np.array(c, dtype=float) for c in
                        [(1, 0, 0), (1, 1, 0), (0, 1, 0), (0, 1, 1), (0, 0, 1), (1, 0, 1)]]
        # Aynı sırada yazıcının karşılıkları: M+Y, Y, C+Y, C, C+M, M
        printer_corners = [np.array(c, dtype=float) for c in
                           [(0, 1, 1, 0), (0, 0, 1, 0), (1, 0, 1, 0), (1, 0, 0, 0), (1, 1, 0, 0), (0, 1, 0, 0)]]
        self.srgb_cusp = hue_table(oklab(self.target_xyz(corner_path(srgb_corners))))
        self.printer_cusp = hue_table(oklab(printed(corner_path(printer_corners))))
        # Ana ve ara renklerin ton açıları: sRGB'ninki yazıcınınkine parça parça doğrusal kayar
        s_anchor = lch(oklab(self.target_xyz(np.array(srgb_corners))))[2]
        p_anchor = lch(oklab(printed(np.array(printer_corners))))[2]
        shift = np.angle(np.exp(1j * (p_anchor - s_anchor)))
        order = np.argsort(s_anchor)
        self.hue_shift = (np.concatenate([s_anchor[order] - 2 * np.pi, s_anchor[order], s_anchor[order] + 2 * np.pi]),
                          np.tile(shift[order], 3))

    def target_xyz(self, rgb_encoded):
        # Siyah nokta dengelemesi: sRGB siyahı yazıcının siyahına, beyaz kağıda
        return self.black_y * WHITE + (1.0 - self.black_y) * srgb_xyz(rgb_encoded)

    def cusp(self, h):
        """Yazıcının bu ton açısındaki en doygun noktası (L, C)"""
        h_table, L_table, C_table = self.printer_cusp
        return np.interp(h, h_table, L_table), np.interp(h, h_table, C_table)

    def map(self, rgb_encoded):
        L, C, h = lch(oklab(self.target_xyz(rgb_encoded)))
        sL, sC = np.interp(h, self.srgb_cusp[0], self.srgb_cusp[1]), np.interp(h, self.srgb_cusp[0], self.srgb_cusp[2])
        # Az doygun renkler yerinde kalır; sRGB'nin sınırına yaklaştıkça yazıcınınkine kayar
        reach = np.clip(C / sC, 0.0, 1.0)
        h2 = h + reach * np.interp(h, *self.hue_shift)
        pL, pC = self.cusp(h2)
        L2 = np.clip(L + reach ** 2 * (pL - sL), self.black_l, 1.0)
        # Doygunluk: dize kadar aynen, sonra sRGB'nin sınırı yazıcınınkine gelecek şekilde
        # sıkıştırılır. Yazıcı o tonda sRGB'den doygunsa (camgöbeği) yalnızca sınıra yakın
        # renkler açılır: saf sRGB rengi tam toner olur, az doygun renkler değişmez.
        knee = CHROMA_KNEE * pC
        span = np.maximum(sC - knee, 1e-9)
        power = np.maximum(span / np.maximum(pC - knee, 1e-9), 1.0)
        x = np.clip((C - knee) / span, 0.0, 1.0)
        compressed = np.where(C > knee, knee + (pC - knee) * (1 - (1 - x) ** power), C)
        expanded = C * (1 + (pC / sC - 1) * reach ** 2)
        C2 = np.where(pC < sC, compressed, expanded)
        # En doygun noktadan koyu renkler: siyaha inen kenarın dışındaysa açıklık ve doygunluk
        # birlikte, gri eksendeki (pL) odağa doğru kenara çekilir (koyu lacivert griye dönmesin)
        Lb = self.black_l
        out = (L2 < pL) & (C2 * (pL - Lb) > pC * (L2 - Lb))
        t = (C2 * (pL - Lb) - pC * (L2 - Lb)) / np.maximum(C2 * (pL - Lb) + pC * (pL - L2), 1e-12)
        t = np.where(out, np.clip(t, 0.0, 1.0), 0.0)
        L2, C2 = L2 + t * (pL - L2), C2 * (1 - t)
        return np.stack([L2, C2 * np.cos(h2), C2 * np.sin(h2)], axis=-1)

    def relative_chroma(self, target):
        """Hedefin doygunluğu, yazıcının o açıklık ve tondaki en büyük doygunluğuna oranla
        (sınır, beyaz-en doygun nokta-siyah üçgeniyle yaklaşık)"""
        L, C, h = lch(target)
        pL, pC = self.cusp(h)
        Lb = self.black_l
        edge = np.where(L <= pL, pC * (L - Lb) / np.maximum(pL - Lb, 1e-9), pC * (1 - L) / np.maximum(1 - pL, 1e-9))
        return np.clip(C / np.maximum(edge, 1e-9), 0.0, 1.0)


# MARK: - Renk tablosu

def black_amount(target, gamut):
    """Düşük GCR: K grilerde K_START'tan koyu tonlarda başlar; doygun renklerde o tonun en
    doygun noktasından koyu tonlarda (saf mavi K'sız kalır, lacivertte K artar)"""
    L, _, h = lch(target)
    rho = gamut.relative_chroma(target)
    pL, _ = gamut.cusp(h)
    start = K_START + rho ** 2 * (pL - K_START)
    darkness = np.clip((start - L) / np.maximum(start - gamut.black_l, 1e-9), 0.0, 1.0)
    return darkness ** K_POWER


def make_lut():
    # Yazıcının en koyu nötr siyahı: K tam, C+M+Y toner sınırının kalanı kadar
    k1 = np.ones(1)
    black_cmy, _ = solve_cmy(np.zeros((1, 3)), k1, np.full((1, 3), 0.4), weights=(1.0, 10.0, 10.0))
    black = np.concatenate([black_cmy[0], k1])
    black_xyz = printed(black)
    black_y = float(black_xyz[1])
    black_l = float(oklab(black_xyz)[0])

    gamut = Gamut(black_y)
    grid = np.arange(NODES) * 255.0 / (NODES - 1)
    r, g, b = np.meshgrid(grid, grid, grid, indexing="ij")  # R en yavaş, B en hızlı
    rgb = np.stack([r, g, b], axis=-1).reshape(-1, 3) / 255.0
    target = gamut.map(rgb)
    k_goal = black_amount(target, gamut)
    cmyk, err = separate(target, k_goal, np.clip(1.0 - rgb, 0.0, 1.0))
    # Kağıt beyazı tam olarak tonersiz kalsın
    cmyk[cmyk < 0.5 / 255] = 0.0
    info = {
        "black": black,
        "black_lab": cielab(black_xyz),
        "black_y": black_y,
        "worst_error": float(err.max()),
        "clipped": int((err > 0.01).sum()),
    }
    return cmyk.reshape(NODES, NODES, NODES, 4), info


# MARK: - Yarım ton

def lattice_period(u, v):
    """Tam sayı (u, v) kafesinin içerdiği en küçük (W, 0) ve (0, H) ötelemeleri"""
    det = abs(u[0] * v[1] - u[1] * v[0])
    width = det // math.gcd(det, abs(u[1]), abs(v[1]))
    height = det // math.gcd(det, abs(u[0]), abs(v[0]))
    return width, height


def bayer(n):
    """n x n süper hücredeki hücrelerin büyüme sırası: art arda büyüyenler komşu olmasın"""
    if n == 3:
        return np.array([[0, 7, 3], [6, 5, 2], [4, 1, 8]])
    order = np.zeros((1, 1), dtype=int)
    while len(order) < n:
        order = np.block([[4 * order, 4 * order + 2], [4 * order + 3, 4 * order + 1]])
    if len(order) != n:
        raise ValueError(f"{n}x{n} süper hücre için sıra tanımlı değil")
    return order


def screen_order(vector, dpi):
    """Bir renk ve çözünürlük için eşik karosu: her pikselin açılma sırası (0 = ilk)"""
    sx, sy = 1200.0 / dpi[0], 1200.0 / dpi[1]
    px, py = vector
    u = np.array([px / sx, py / sy])   # hücre vektörü, cihaz pikseli cinsinden
    v = np.array([-py / sx, px / sy])  # fiziksel olarak dik ve aynı uzunlukta
    # Süper hücre: n hücrelik kenar tam sayıya otursun ve en az ~240 gri düzeyi olsun
    # (n x n hücre sırayla büyür; tek hücrede düzey sayısı hücrenin piksel sayısı kadar)
    cell_area = abs(u[0] * v[1] - u[1] * v[0])
    for n in range(1, 13):
        su, sv = n * u, n * v
        if np.allclose(su, np.round(su), atol=1e-9) and np.allclose(sv, np.round(sv), atol=1e-9) \
                and n * n * cell_area >= 240:
            iu, iv = tuple(int(round(c)) for c in su), tuple(int(round(c)) for c in sv)
            width, height = lattice_period(iu, iv)
            break
    else:
        raise ValueError(f"{vector} için tam sayı süper hücre bulunamadı")

    ys, xs = np.mgrid[0:height, 0:width]
    points = np.stack([xs + 0.5, ys + 0.5], axis=-1)
    st = points @ np.linalg.inv(np.stack([u, v], axis=1)).T  # hücre koordinatları
    cell = np.floor(st)
    f = (st - cell) * 2 - 1  # hücre içinde -1..1, merkez 0
    ax, ay = np.abs(f[..., 0]), np.abs(f[..., 1])
    # Öklid noktası: açık tonlarda yuvarlak nokta, %50'de dama, koyuda yuvarlak boşluk
    spot = np.where(ax + ay <= 1, 1 - (ax ** 2 + ay ** 2), (ax - 1) ** 2 + (ay - 1) ** 2 - 1)
    # Süper hücredeki hücreler sırayla büyür; eşitlikler açıyla bozulur
    cell_rank = bayer(n)[cell[..., 0].astype(int) % n, cell[..., 1].astype(int) % n]
    key = -spot + (cell_rank + 0.5) / (n * n) * (2.0 / cell_area)
    tie = np.arctan2(f[..., 1], f[..., 0])
    order = np.lexsort((tie.ravel(), key.ravel()))
    rank = np.empty(width * height, dtype=int)
    rank[order] = np.arange(width * height)
    lpi = 1200.0 / math.hypot(px, py)
    angle = math.degrees(math.atan2(py, px))
    return rank.reshape(height, width), {"n": n, "size": (width, height), "lpi": lpi, "angle": angle}


def thresholds(rank, at_40, gray=False):
    """Açılma sırası → eşik. Kazanç dengelenir: pikselin açıldığı ton kazanç(sıra/N)."""
    tone = gain((rank + 0.5) / rank.size, at_40)  # kağıtta görünen kaplama
    if gray:
        # Gri değer (sRGB) → K kaplaması = 1 - parlaklık (siyah nokta K'nın siyahına)
        level = 255.0 * srgb_encode(1.0 - tone)
    else:
        level = 255.0 * (1.0 - tone)
    return np.clip(np.floor(level + 1e-9) + 1, 1, 255).astype(int)


# MARK: - Dosyalar

def write_screen(path, values):
    height, width = values.shape
    with open(path, "w", newline="\n") as fp:
        fp.write(f"{width} {height}\n")
        for row in values:
            fp.write(" ".join(str(v) for v in row) + "\n")


def write_lut(path, cmyk):
    values = np.clip(np.round(255.0 * (1.0 - cmyk)), 0, 255).astype(int).reshape(-1, 4)
    with open(path, "w", newline="\n") as fp:
        fp.write(f"{NODES} {NODES} {NODES} 4\n")
        for c, m, y, k in values:
            fp.write(f"{c} {m} {y} {k}\n")


def main():
    parser = argparse.ArgumentParser(description="PrinterManager'ın CLP-300 renk verisini üretir")
    parser.add_argument("output", nargs="?", default=DEFAULT_OUTPUT, help="çıktı klasörü")
    parser.add_argument("--gain-at-40", type=float, default=DOT_GAIN_AT_40,
                        help=f"%%40 sayısal kaplamanın kağıtta görünen kaplaması (varsayılan {DOT_GAIN_AT_40})")
    args = parser.parse_args()
    output = args.output
    os.makedirs(output, exist_ok=True)

    cmyk, info = make_lut()
    lab = info["black_lab"]
    print(f"En koyu siyah: CMYK {np.round(info['black'] * 100).astype(int)} → L*{lab[0]:.1f} a*{lab[1]:.1f} b*{lab[2]:.1f}")
    print(f"Renk tablosu: {info['clipped']} / {NODES ** 3} düğüm yazıcının gamutu dışında kırpıldı "
          f"(en büyük fark {info['worst_error']:.3f} Oklab)")
    for name in LUT_NAMES.values():
        write_lut(os.path.join(output, name), cmyk)

    for suffix, dpi in RESOLUTIONS.items():
        for color, vector in SCREENS.items():
            rank, meta = screen_order(vector, dpi)
            write_screen(os.path.join(output, f"{color}HT_{suffix}"), thresholds(rank, args.gain_at_40))
            if color == "Black":
                write_screen(os.path.join(output, f"GrayHT_{suffix}"), thresholds(rank, args.gain_at_40, gray=True))
            print(f"{color}HT_{suffix}: {meta['size'][0]}x{meta['size'][1]}, {meta['angle']:.2f}°, "
                  f"{meta['lpi']:.1f} lpi, süper hücre {meta['n']}x{meta['n']}")
    print(f"Yazıldı: {output}")


if __name__ == "__main__":
    main()
