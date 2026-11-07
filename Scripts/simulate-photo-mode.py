#!/usr/bin/env python3
"""Fotoğraf modunun renk verisini yazıcıya göndermeden karşılaştırır.

    python3 Scripts/simulate-photo-mode.py --raster <clp300-raster> --foo2qpdl <foo2qpdl> \\
        --out <klasör> AD=<veri-klasörü> [AD=<veri-klasörü> ...]

Örnek: PrinterManager=PrinterManager/Resources/ColorTables/CLP-300
       Samsung=/Library/Printers/Samsung/CLP-300

Her veri kümesine bir sütun (en çok üç) ayrılan bir A4 test sayfası (gri ve renk
rampaları, koyu tonlar, renk kartı yamaları, çizimle üretilmiş bir "fotoğraf")
uygulamayla aynı komutlarla basılır:
gs (ppmraw) | clp300-raster | foo2qpdl. Sonra bitcmyk açılır, yamalar ve küçük
bloklar ortalanır, basit nokta kazancı (%40 → %50) ve make-colour-tables.py'deki
yazıcı modeli uygulanır. Model kaba bir tahmindir: sonuçlar veri kümelerini
birbiriyle karşılaştırmak içindir, gerçek baskının ölçümü değildir.

Çıktılar: rapor.md, her veri kümesi için önizleme PNG'si, birden çok veri kümesi
varsa yan yana karşılaştırma sayfası (her sütun kendi veri kümesiyle, 1200x600) hem
PNG önizlemesi hem yazıcıya gönderilebilir ham QPDL olarak.
Gerekenler: Python 3, numpy, Pillow, Ghostscript (gs).
"""
import argparse
import importlib.util
import io
import os
import subprocess
import sys
import zlib

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("tables", os.path.join(HERE, "make-colour-tables.py"))
model = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(model)

PAGE_W, PAGE_H = 595.276, 841.89  # A4, pt
GEOMETRY = {  # QPDLDriver.swift ile aynı: genişlik, yükseklik, kenar kırpma
    "600x600": (4960, 7016, 75, 100),
    "1200x600": (9920, 7016, 150, 100),
    "1200x1200": (9920, 14032, 150, 100),
}
MARGIN, GUTTER = 28.0, 14.0

# Renk kartı yamaları: yaygın yayımlanan 24 yamalı kartın yaklaşık sRGB değerleri
CHECKER = [
    ("koyu ten", (115, 82, 68)), ("açık ten", (194, 150, 130)), ("gökyüzü", (98, 122, 157)),
    ("yaprak", (87, 108, 67)), ("mavi çiçek", (133, 128, 177)), ("mavimsi yeşil", (103, 189, 170)),
    ("turuncu", (214, 126, 44)), ("mor-mavi", (80, 91, 166)), ("orta kırmızı", (193, 90, 99)),
    ("mor", (94, 60, 108)), ("sarı-yeşil", (157, 188, 64)), ("turuncu-sarı", (224, 163, 46)),
    ("mavi", (56, 61, 150)), ("yeşil", (70, 148, 73)), ("kırmızı", (175, 54, 60)),
    ("sarı", (231, 199, 31)), ("macenta", (187, 86, 149)), ("camgöbeği", (8, 133, 161)),
    ("beyaz", (243, 243, 242)), ("gri 8", (200, 200, 200)), ("gri 6.5", (160, 160, 160)),
    ("gri 5", (122, 122, 121)), ("gri 3.5", (85, 85, 85)), ("siyah", (52, 52, 52)),
]
RAMPS = [  # ad, beyazdan (ya da siyahtan) tam renge
    ("C", lambda v: (255 - v, 255, 255)), ("M", lambda v: (255, 255 - v, 255)),
    ("Y", lambda v: (255, 255, 255 - v)), ("R", lambda v: (255, 255 - v, 255 - v)),
    ("G", lambda v: (255 - v, 255, 255 - v)), ("B", lambda v: (255 - v, 255 - v, 255)),
    ("koyu R", lambda v: (v, 0, 0)), ("koyu G", lambda v: (0, v, 0)), ("koyu B", lambda v: (0, 0, v)),
]
RAMP_STEPS = [0, 32, 64, 96, 128, 160, 192, 224, 255]


# MARK: - Test sayfası

def photo(width, height):
    """Çizimle üretilmiş, fotoğrafa benzeyen sahne: gökyüzü, tepeler, ten, doygun nesneler, gölge"""
    y = np.linspace(0, 1, height)[:, None, None]
    sky = np.array([62, 118, 196]) * (1 - y) + np.array([196, 218, 238]) * y
    image = Image.fromarray(np.broadcast_to(sky, (height, width, 3)).astype(np.uint8))
    draw = ImageDraw.Draw(image)
    w, h = width, height
    draw.ellipse([w * 0.72, h * 0.08, w * 0.86, h * 0.30], fill=(255, 236, 170))
    for i, (color, base) in enumerate([((96, 140, 72), 0.55), ((62, 112, 52), 0.65), ((36, 78, 40), 0.76)]):
        points = [(0, h)]
        for x in range(0, w + 8, 8):
            points.append((x, h * (base - 0.08 * np.sin(x / w * (5 + i) + i) - 0.04 * np.sin(x / w * 17 + 2 * i))))
        points.append((w, h))
        draw.polygon(points, fill=color)
    image = image.filter(ImageFilter.GaussianBlur(2))
    draw = ImageDraw.Draw(image)
    # Ten: yuvarlak, ışıktan gölgeye
    face = Image.new("RGB", (int(w * 0.26), int(h * 0.62)))
    fy, fx = np.mgrid[0:face.height, 0:face.width]
    d = np.hypot((fx - face.width * 0.38) / face.width, (fy - face.height * 0.35) / face.height)
    skin = np.array([246, 212, 186]) * (1 - d[..., None]) + np.array([150, 92, 66]) * d[..., None]
    face = Image.fromarray(np.clip(skin, 0, 255).astype(np.uint8))
    mask = Image.new("L", face.size, 0)
    ImageDraw.Draw(mask).ellipse([0, 0, face.width - 1, face.height - 1], fill=255)
    image.paste(face, (int(w * 0.06), int(h * 0.22)), mask.filter(ImageFilter.GaussianBlur(3)))
    # Doygun nesneler ve koyu gölge
    for (cx, cy, r, color) in [(0.45, 0.80, 0.07, (204, 32, 44)), (0.58, 0.82, 0.06, (242, 196, 36)),
                               (0.70, 0.80, 0.07, (36, 70, 168)), (0.82, 0.83, 0.05, (150, 40, 140))]:
        draw.ellipse([w * (cx - r), h * cy - w * r, w * (cx + r), h * cy + w * r], fill=color)
    shade = np.linspace(1, 0, int(h * 0.12))[:, None, None]
    strip = np.broadcast_to(np.array([20, 24, 60]) * shade, (len(shade), w, 3)).astype(np.uint8)
    image.paste(Image.fromarray(strip), (0, h - len(shade)))
    return image.filter(ImageFilter.GaussianBlur(1.2))


class Chart:
    """Eş sütunlu test sayfası (her veri kümesine bir sütun); yamaların yerini (pt) ölçüm için saklar"""

    def __init__(self, columns):
        self.width = (PAGE_W - 2 * MARGIN - (columns - 1) * GUTTER) / columns
        self.ops = []
        self.patches = {}  # ad → (x, y, w, h) pt, sol sütunda; y yukarıdan
        self.image = None
        self.image_box = None

    def rect(self, x, y, w, h, rgb):
        r, g, b = (c / 255 for c in rgb)
        self.ops.append(f"{r:.4f} {g:.4f} {b:.4f} rg {x:.2f} {PAGE_H - y - h:.2f} {w:.2f} {h:.2f} re f")

    def text(self, x, y, size, string):
        safe = string.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")
        self.ops.append(f"0 g BT /F1 {size} Tf {x:.2f} {PAGE_H - y - size:.2f} Td ({safe}) Tj ET")

    def column(self, x0, title):
        y = MARGIN
        self.text(x0, y, 9, title)
        y += 16
        width = self.width
        # Gri: 17 yama (tablonun düğümleri) ve 256 adımlık şerit
        step = width / 17
        for i in range(17):
            v = round(255 * i / 16)
            self.rect(x0 + i * step, y, step, 24, (v, v, v))
            self.patches.setdefault(("gri", v), (MARGIN + i * step, y, step, 24))
        y += 28
        for i in range(256):
            self.rect(x0 + i * width / 256, y, width / 256 + 0.05, 12, (i, i, i))
        y += 18
        # Rampalar
        step = width / len(RAMP_STEPS)
        for name, color in RAMPS:
            for i, v in enumerate(RAMP_STEPS):
                self.rect(x0 + i * step, y, step, 17, color(v))
                self.patches.setdefault((name, v), (MARGIN + i * step, y, step, 17))
            y += 19
        y += 6
        # Renk kartı
        step_x, step_y = width / 6, 28
        for i, (name, rgb) in enumerate(CHECKER):
            px, py = x0 + (i % 6) * step_x, y + (i // 6) * step_y
            self.rect(px, py, step_x - 2, step_y - 2, rgb)
            self.patches.setdefault(("kart", name), (MARGIN + (i % 6) * step_x, py, step_x - 2, step_y - 2))
        y += 4 * step_y + 8
        # Fotoğraf (toner için sayfanın altı boş kalır)
        height = min(width * 1.25, PAGE_H - MARGIN - y)
        self.ops.append(f"q {width:.2f} 0 0 {height:.2f} {x0:.2f} {PAGE_H - y - height:.2f} cm /Im1 Do Q")
        if self.image is None:
            self.image = photo(int(width / 72 * 200), int(height / 72 * 200))
            self.image_box = (MARGIN, y, width, height)

    def pdf(self):
        content = "\n".join(self.ops).encode("cp1252", errors="replace")
        pixels = zlib.compress(self.image.tobytes(), 9)
        objects = [
            b"<< /Type /Catalog /Pages 2 0 R >>",
            b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {PAGE_W} {PAGE_H}] /Contents 4 0 R "
            f"/Resources << /Font << /F1 5 0 R >> /XObject << /Im1 6 0 R >> >> >>".encode(),
            b"<< /Length %d >>\nstream\n" % len(content) + content + b"\nendstream",
            b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>",
            f"<< /Type /XObject /Subtype /Image /Width {self.image.width} /Height {self.image.height} "
            f"/ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /FlateDecode /Length {len(pixels)} >>\nstream\n".encode()
            + pixels + b"\nendstream",
        ]
        out = io.BytesIO()
        out.write(b"%PDF-1.4\n")
        offsets = []
        for number, body in enumerate(objects, 1):
            offsets.append(out.tell())
            out.write(b"%d 0 obj\n" % number + body + b"\nendobj\n")
        xref = out.tell()
        out.write(b"xref\n0 %d\n0000000000 65535 f \n" % (len(objects) + 1))
        for offset in offsets:
            out.write(b"%010d 00000 n \n" % offset)
        out.write(b"trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (len(objects) + 1, xref))
        return out.getvalue()


def make_chart(names):
    chart = Chart(len(names))
    for i, name in enumerate(names):
        chart.column(MARGIN + i * (chart.width + GUTTER), f"{'ABC'[i]}: {name}")
    return chart


# MARK: - Baskı hattı (QPDLDriver.swift ile aynı komutlar)

def render(pdf, resolution, path):
    width, height, _, _ = GEOMETRY[resolution]
    subprocess.run([
        "gs", "-q", "-dBATCH", "-dSAFER", "-dQUIET", "-dNOPAUSE", "-sstdout=%stderr", "-sPAPERSIZE=a4",
        f"-g{width}x{height}", f"-r{resolution}", "-sDEVICE=ppmraw", "-dInterpolateControl=-1",
        "-dFIXEDMEDIA", "-dPDFFitPage", f"-sOutputFile={path}", "-dFirstPage=1", "-dLastPage=1", pdf,
    ], check=True)


def separate(raster, tables, resolution, ppm, path):
    with open(ppm, "rb") as src, open(path, "wb") as dst:
        subprocess.run([raster, tables, resolution], stdin=src, stdout=dst, check=True)


def encode(foo2qpdl, resolution, bitcmyk, path):
    width, height, clip_x, clip_y = GEOMETRY[resolution]
    clip = f"{clip_x}x{clip_y}"
    with open(bitcmyk, "rb") as src, open(path, "wb") as dst:
        subprocess.run([foo2qpdl, f"-r{resolution}", f"-g{width}x{height}", "-p2", "-m0", "-n1", "-d1", "-s1",
                        "-z0", "-c", "-u", clip, "-l", clip, "-a50,50,50,50,50,50", "-J", "", "-U", "", "-D0"],
                       stdin=src, stdout=dst, stderr=subprocess.DEVNULL, check=True)
    return os.path.getsize(path)


# MARK: - Benzetim

def load_bitcmyk(path, resolution):
    width, height, _, _ = GEOMETRY[resolution]
    return np.fromfile(path, dtype=np.uint8).reshape(height, (width + 1) // 2)


def coverage(page, x0, y0, x1, y1):
    """[x0,x1) x [y0,y1) piksel bölgesinde C, M, Y, K sayısal kaplaması"""
    block = page[y0:y1, x0 // 2:(x1 + 1) // 2]
    nibbles = np.stack([block >> 4, block & 15], axis=-1).reshape(block.shape[0], -1)
    nibbles = nibbles[:, x0 % 2:x0 % 2 + (x1 - x0)]
    return np.array([((nibbles >> bit) & 1).mean() for bit in (3, 2, 1, 0)])


def appearance(digital):
    """Sayısal kaplama → kağıttaki renk (XYZ): nokta kazancı, sonra yazıcı modeli"""
    return model.printed(model.gain(np.asarray(digital, dtype=float)))


def to_pixels(box, resolution, shrink=0.2):
    x, y, w, h = box
    dpi_x, dpi_y = (int(v) for v in resolution.split("x"))
    sx, sy = dpi_x / 72, dpi_y / 72
    return (int((x + w * shrink) * sx), int((y + h * shrink) * sy),
            int((x + w * (1 - shrink)) * sx), int((y + h * (1 - shrink)) * sy))


def preview(page, resolution, x_range=None, dpi=100):
    """Sayfayı 100 dpi bloklarına ortalayıp modelden sRGB görüntü üretir"""
    width, height, _, _ = GEOMETRY[resolution]
    dpi_x, dpi_y = (int(v) for v in resolution.split("x"))
    bx, by = dpi_x // dpi, dpi_y // dpi
    rows = []
    for top in range(0, height - by + 1, by * 50):
        strip = page[top:min(top + by * 50, height - height % by)]
        bits = np.stack([strip >> 4, strip & 15], axis=-1).reshape(strip.shape[0], -1)[:, :width]
        bits = bits[:, :width - width % bx]
        planes = [((bits >> bit) & 1).reshape(strip.shape[0] // by, by, -1, bx).mean(axis=(1, 3))
                  for bit in (3, 2, 1, 0)]
        rows.append(np.stack(planes, axis=-1))
    digital = np.concatenate(rows)
    xyz = appearance(digital)
    rgb = model.srgb_encode(np.clip(xyz @ np.linalg.inv(model.M_XYZ).T, 0, 1))
    return Image.fromarray(np.round(rgb * 255).astype(np.uint8))


def delta_e(lab1, lab2):
    return float(np.linalg.norm(np.asarray(lab1) - np.asarray(lab2)))


def measure(page, resolution, chart):
    results = {}
    for key, box in chart.patches.items():
        x0, y0, x1, y1 = to_pixels(box, resolution)
        digital = coverage(page, x0, y0, x1, y1)
        results[key] = (digital, model.cielab(appearance(digital)))
    return results


def ink_usage(page):
    """Sayfanın tamamında renk başına ortalama sayısal kaplama (%)"""
    totals = np.zeros(4)
    for top in range(0, page.shape[0], 1000):
        strip = page[top:top + 1000]
        for i, bit in enumerate((3, 2, 1, 0)):
            totals[i] += (((strip >> 4) >> bit) & 1).sum() + (((strip & 15) >> bit) & 1).sum()
    return 100 * totals / (page.size * 2)


# MARK: - Rapor

def report(names, resolutions, results, sizes, inks, chart):
    lines = ["# Fotoğraf modu benzetimi", "",
             "Model: nokta kazancı %40 → %50, make-colour-tables.py'deki toner varsayımları. "
             "Sayılar veri kümelerini karşılaştırmak içindir; gerçek baskı ölçümü değildir.", ""]
    res = "1200x600" if "1200x600" in resolutions else resolutions[0]
    lines += [f"## Gri rampa ({res}): L* ve renk sapması C*ab", "",
              "| sRGB | hedef L* | " + " | ".join(f"{n} L* | {n} C*ab | {n} C/M/Y/K %" for n in names) + " |",
              "|---" * (2 + 3 * len(names)) + "|"]
    for i in range(17):
        v = round(255 * i / 16)
        target = model.cielab(model.srgb_xyz(np.array([v, v, v]) / 255))[0]
        row = f"| {v} | {target:.1f} |"
        for n in names:
            digital, lab = results[n][res][("gri", v)]
            row += f" {lab[0]:.1f} | {np.hypot(lab[1], lab[2]):.1f} | {'/'.join(str(round(100 * c)) for c in digital)} |"
        lines.append(row)
    lines.append("")
    lines += ["## Özet", "", "| ölçüt | " + " | ".join(names) + " |", "|---" * (1 + len(names)) + "|"]

    def metric(title, fn):
        lines.append(f"| {title} | " + " | ".join(fn(n) for n in names) + " |")

    def grey(n):
        return np.array([results[n][res][("gri", round(255 * i / 16))][1] for i in range(17)])

    metric("gri: en büyük renk sapması C*ab", lambda n: f"{np.hypot(grey(n)[:, 1], grey(n)[:, 2]).max():.1f}")
    metric("gri: ortalama renk sapması C*ab", lambda n: f"{np.hypot(grey(n)[:, 1], grey(n)[:, 2]).mean():.1f}")
    metric("gri: L* tekdüze artıyor", lambda n: "evet" if np.all(np.diff(grey(n)[:, 0]) > 0) else "HAYIR")
    metric("en koyu siyah L*", lambda n: f"{grey(n)[0, 0]:.1f}")
    metric("sRGB 128 grisi L* (hedef 53,4)", lambda n: f"{grey(n)[8, 0]:.1f}")
    for name, _ in RAMPS:
        metric(f"{name} rampası tekdüze", lambda n, name=name: "evet" if np.all(np.diff(
            [results[n][res][(name, v)][1][0] for v in RAMP_STEPS]) * (1 if name.startswith("koyu") else -1) > 0) else "HAYIR")

    def checker_error(n):
        errors = []
        for name, rgb in CHECKER:
            reference = model.cielab(model.srgb_xyz(np.array(rgb) / 255))
            errors.append(delta_e(results[n][res][("kart", name)][1], reference))
        return f"{np.mean(errors):.1f} / {np.max(errors):.1f}"

    metric("renk kartı ΔE*ab sRGB'ye göre (ort./en çok)", checker_error)
    for r in resolutions:
        metric(f"QPDL boyutu {r}", lambda n, r=r: f"{sizes[n][r] / 1e6:.2f} MB")
    metric(f"toner kaplaması C/M/Y/K % ({res}, sayfa)", lambda n: "/".join(f"{v:.1f}" for v in inks[n][res]))
    lines.append("")
    if "karşılaştırma sayfası" in inks:
        lines += ["Karşılaştırma sayfasının toner kaplaması C/M/Y/K %: "
                  + "/".join(f"{v:.1f}" for v in inks["karşılaştırma sayfası"]), ""]
    if len(names) > 1:
        a, b = names[0], names[1]
        lines += [f"## Renk kartı: {a} ile {b} arası fark ({res})", "",
                  f"| yama | sRGB L*a*b* | {a} | {b} | ΔE*ab |", "|---|---|---|---|---|"]
        for name, rgb in CHECKER:
            ref = model.cielab(model.srgb_xyz(np.array(rgb) / 255))
            la, lb = results[a][res][("kart", name)][1], results[b][res][("kart", name)][1]
            fmt = lambda lab: f"{lab[0]:.0f} {lab[1]:+.0f} {lab[2]:+.0f}"
            lines.append(f"| {name} | {fmt(ref)} | {fmt(la)} | {fmt(lb)} | {delta_e(la, lb):.1f} |")
        lines.append("")
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--raster", required=True)
    parser.add_argument("--foo2qpdl", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--resolutions", default="600x600,1200x600,1200x1200")
    parser.add_argument("tables", nargs="+", help="AD=klasör")
    args = parser.parse_args()
    os.makedirs(args.out, exist_ok=True)
    sets = [t.split("=", 1) for t in args.tables]
    if len(sets) > 3:
        parser.error("en çok üç veri kümesi")
    names = [n for n, _ in sets]
    resolutions = args.resolutions.split(",")

    chart = make_chart(names)
    pdf = os.path.join(args.out, "test-sayfasi.pdf")
    with open(pdf, "wb") as fp:
        fp.write(chart.pdf())
    chart.image.save(os.path.join(args.out, "fotograf-orijinal.png"))

    results = {n: {} for n in names}
    sizes = {n: {} for n in names}
    inks = {n: {} for n in names}
    for resolution in resolutions:
        ppm = os.path.join(args.out, f"sayfa-{resolution}.ppm")
        render(pdf, resolution, ppm)
        pages = {}
        for name, directory in sets:
            raw = os.path.join(args.out, f"{name}-{resolution}.bitcmyk")
            separate(args.raster, directory, resolution, ppm, raw)
            sizes[name][resolution] = encode(args.foo2qpdl, resolution, raw,
                                             os.path.join(args.out, f"{name}-{resolution}.qpdl"))
            page = load_bitcmyk(raw, resolution)
            results[name][resolution] = measure(page, resolution, chart)
            inks[name][resolution] = ink_usage(page)
            if resolution == "1200x600":
                preview(page, resolution).save(os.path.join(args.out, f"onizleme-{name}.png"))
            pages[name] = (raw, page)
            print(f"{name} {resolution}: QPDL {sizes[name][resolution] / 1e6:.2f} MB", file=sys.stderr)
        # Yan yana karşılaştırma: her sütun kendi veri kümesinden
        if len(names) > 1 and resolution == "1200x600":
            sheet = pages[names[0]][1].copy()
            for i, name in enumerate(names[1:], 1):
                start = int((MARGIN + i * (chart.width + GUTTER) - GUTTER / 2) / 72 * 1200) // 2
                sheet[:, start:] = pages[name][1][:, start:]
            raw = os.path.join(args.out, "karsilastirma-1200x600.bitcmyk")
            sheet.tofile(raw)
            size = encode(args.foo2qpdl, resolution, raw, os.path.join(args.out, "karsilastirma-1200x600.qpdl"))
            preview(sheet, resolution).save(os.path.join(args.out, "karsilastirma-onizleme.png"))
            inks["karşılaştırma sayfası"] = ink_usage(sheet)
            print(f"karşılaştırma sayfası: QPDL {size / 1e6:.2f} MB, kaplama C/M/Y/K % "
                  + "/".join(f"{v:.1f}" for v in inks["karşılaştırma sayfası"]), file=sys.stderr)
            os.remove(raw)
        for name in names:
            os.remove(pages[name][0])
        os.remove(ppm)

    text = report(names, resolutions, results, sizes, inks, chart)
    with open(os.path.join(args.out, "rapor.md"), "w") as fp:
        fp.write(text)
    print(text)


if __name__ == "__main__":
    main()
