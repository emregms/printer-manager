#!/usr/bin/env python3
"""Ekran görüntüleri için 6 sayfalık renkli örnek A4 PDF üretir (Pillow gerekir).

    python3 Scripts/sample-document.py <çıktı.pdf>

Sayfalar kodla çizilir; telifli görsel ya da kişisel fotoğraf içermez.
"""
import math
import random
import sys
import zlib

from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H = 1240, 1754  # A4, 150 dpi
FONT_DIRS = ["/System/Library/Fonts/Supplemental/", "/Library/Fonts/"]


def font(size, bold=False):
    names = ["Arial Bold.ttf", "Arial.ttf"] if bold else ["Arial.ttf"]
    for directory in FONT_DIRS:
        for name in names:
            try:
                return ImageFont.truetype(directory + name, size)
            except OSError:
                pass
    return ImageFont.load_default()


def gradient(top, bottom, size=(W, H)):
    image = Image.new("RGB", size)
    draw = ImageDraw.Draw(image)
    for y in range(size[1]):
        t = y / (size[1] - 1)
        draw.line([(0, y), (size[0], y)], fill=tuple(int(a + (b - a) * t) for a, b in zip(top, bottom)))
    return image


def mountains(draw, base, height, color, seed, rough=0.35):
    rng = random.Random(seed)
    points, y = [], base - height * 0.5
    for x in range(0, W + 40, 40):
        y = min(base - 40, max(base - height, y + rng.uniform(-height * rough, height * rough) * 0.4))
        points.append((x, y))
    draw.polygon([(0, H)] + points + [(W, H)], fill=color)


def landscape():
    page = gradient((255, 170, 120), (90, 150, 220), (W, 1100))
    draw = ImageDraw.Draw(page)
    draw.ellipse((780, 220, 980, 420), fill=(255, 230, 160))
    mountains(draw, 760, 420, (110, 90, 140), 3)
    mountains(draw, 820, 300, (70, 70, 110), 7)
    lake = gradient((60, 110, 170), (20, 50, 90), (W, 380))
    page.paste(lake, (0, 820))
    for i in range(18):
        y = 840 + i * 18
        draw.line([(820 - i * 6, y), (940 + i * 6, y)], fill=(255, 210, 150), width=3)
    full = Image.new("RGB", (W, H), "white")
    full.paste(page.filter(ImageFilter.GaussianBlur(1.2)), (0, 0))
    draw = ImageDraw.Draw(full)
    draw.text((90, 1200), "Göl Kenarında Gün Batımı", font=font(64, True), fill=(40, 40, 60))
    draw.text((90, 1290), "Fotoğraf modu: Samsung'un renk tablosuyla doğal tonlar", font=font(34), fill=(90, 90, 110))
    return full


def color_test():
    page = Image.new("RGB", (W, H), "white")
    draw = ImageDraw.Draw(page)
    draw.text((90, 90), "Renk Testi", font=font(72, True), fill=(30, 30, 30))
    colors = [(0, 174, 239), (236, 0, 140), (255, 242, 0), (0, 0, 0), (237, 28, 36), (0, 166, 81), (46, 49, 146)]
    for i, color in enumerate(colors):
        draw.rectangle((90 + i * 152, 230, 220 + i * 152, 480), fill=color)
    for row, color in enumerate(colors[:4]):
        for step in range(10):
            t = step / 9
            fill = tuple(int(255 + (c - 255) * t) for c in color)
            draw.rectangle((90 + step * 106, 560 + row * 130, 190 + step * 106, 670 + row * 130), fill=fill)
    hue = Image.new("RGB", (1060, 260))
    hue_draw = ImageDraw.Draw(hue)
    for x in range(1060):
        h = x / 1060 * 6
        k = lambda n: max(0, min(1, abs((h + n) % 6 - 3) - 1))
        hue_draw.line([(x, 0), (x, 260)], fill=(int(255 * k(0)), int(255 * k(4)), int(255 * k(2))))
    page.paste(hue, (90, 1120))
    draw.text((90, 1440), "Ton geçişleri ve ana renkler", font=font(34), fill=(90, 90, 90))
    return page


def report():
    page = Image.new("RGB", (W, H), "white")
    draw = ImageDraw.Draw(page)
    draw.rectangle((0, 0, W, 260), fill=(32, 64, 120))
    draw.text((90, 90), "Aylık Rapor", font=font(76, True), fill="white")
    values = [42, 58, 51, 73, 66, 88]
    labels = ["Oca", "Şub", "Mar", "Nis", "May", "Haz"]
    for i, (value, label) in enumerate(zip(values, labels)):
        x = 130 + i * 160
        draw.rectangle((x, 900 - value * 6, x + 100, 900), fill=(66, 133, 244) if i % 2 else (52, 168, 83))
        draw.text((x + 18, 920), label, font=font(32), fill=(60, 60, 60))
    start = -90
    for share, color in zip([40, 25, 20, 15], [(234, 67, 53), (251, 188, 5), (52, 168, 83), (66, 133, 244)]):
        draw.pieslice((340, 1060, 900, 1620), start, start + share * 3.6, fill=color)
        start += share * 3.6
    return page


def article():
    page = Image.new("RGB", (W, H), "white")
    draw = ImageDraw.Draw(page)
    draw.text((90, 100), "Yazıcı Bakım Notları", font=font(64, True), fill=(20, 20, 20))
    draw.rectangle((90, 200, 1150, 206), fill=(236, 0, 140))
    words = ("kayış temizleyici her sayfadan sonra çalışır ve yazıcı hazır olunca sıradaki sayfa "
             "gönderilir böylece toner birikmez ve baskılar temiz çıkar çift yönlü baskıda önce tek "
             "sayfalar basılır sonra kağıtlar çevrilir").split()
    rng = random.Random(5)
    y = 260
    for paragraph in range(6):
        for line in range(6 if paragraph % 2 else 5):
            text = " ".join(rng.choice(words) for _ in range(11)).capitalize()
            draw.text((90, y), text, font=font(30), fill=(50, 50, 50))
            y += 46
        y += 40
    draw.rectangle((90, y, 1150, y + 260), fill=(255, 244, 214))
    draw.text((120, y + 40), "İpucu: Fotoğraflar için Fotoğraf Modu'nu açın.", font=font(34, True), fill=(140, 90, 0))
    return page


def sunset():
    page = gradient((255, 120, 60), (60, 30, 90), (W, 1250))
    draw = ImageDraw.Draw(page)
    draw.ellipse((420, 620, 820, 1020), fill=(255, 200, 90))
    draw.rectangle((0, 900, W, 1250), fill=(30, 40, 80))
    for i in range(30):
        y = 920 + i * 10
        draw.line([(620 - 200 + i * 5, y), (620 + 200 - i * 5, y)], fill=(255, 170, 80), width=2)
    trunk = [(150 + 30 * math.sin(t / 10), 1250 - t * 18) for t in range(30)]
    draw.line(trunk, fill=(20, 15, 30), width=26)
    top = trunk[-1]
    for angle in range(0, 360, 40):
        a = math.radians(angle)
        draw.line([top, (top[0] + 260 * math.cos(a), top[1] + 120 * math.sin(a) + 60)], fill=(20, 15, 30), width=18)
    full = Image.new("RGB", (W, H), "white")
    full.paste(page, (0, 0))
    draw = ImageDraw.Draw(full)
    draw.text((90, 1340), "Sahilde Akşam", font=font(64, True), fill=(40, 30, 60))
    return full


def calendar():
    page = Image.new("RGB", (W, H), "white")
    draw = ImageDraw.Draw(page)
    draw.text((90, 100), "Kasım", font=font(80, True), fill=(237, 28, 36))
    days = ["Pzt", "Sal", "Çar", "Per", "Cum", "Cmt", "Paz"]
    for i, day in enumerate(days):
        draw.text((110 + i * 150, 280), day, font=font(34, True), fill=(80, 80, 80))
    for n in range(30):
        col, row = (n + 5) % 7, (n + 5) // 7
        x, y = 90 + col * 150, 360 + row * 190
        fill = (255, 235, 235) if col >= 5 else (240, 245, 255)
        draw.rounded_rectangle((x, y, x + 136, y + 170), 16, fill=fill)
        draw.text((x + 16, y + 12), str(n + 1), font=font(40, True), fill=(50, 50, 70))
    return page


def write_pdf(pages, path):
    """Her sayfası tek bir Flate sıkıştırılmış RGB görsel olan PDF (JPEG desteği gerekmez)"""
    objects = []

    def add(body):
        objects.append(body)
        return len(objects)

    page_ids = []
    pages_id = len(pages) * 3 + 1
    for image in pages:
        data = zlib.compress(image.convert("RGB").tobytes(), 9)
        image_id = add(b"<< /Type /XObject /Subtype /Image /Width %d /Height %d /ColorSpace /DeviceRGB "
                       b"/BitsPerComponent 8 /Filter /FlateDecode /Length %d >>\nstream\n" % (W, H, len(data))
                       + data + b"\nendstream")
        content = b"q 595.28 0 0 841.89 0 0 cm /Im Do Q"
        content_id = add(b"<< /Length %d >>\nstream\n%s\nendstream" % (len(content), content))
        page_ids.append(add(b"<< /Type /Page /Parent %d 0 R /MediaBox [0 0 595.28 841.89] "
                            b"/Resources << /XObject << /Im %d 0 R >> >> /Contents %d 0 R >>"
                            % (pages_id, image_id, content_id)))
    kids = b" ".join(b"%d 0 R" % i for i in page_ids)
    add(b"<< /Type /Pages /Kids [%s] /Count %d >>" % (kids, len(page_ids)))
    catalog_id = add(b"<< /Type /Catalog /Pages %d 0 R >>" % pages_id)

    out = bytearray(b"%PDF-1.4\n")
    offsets = []
    for number, body in enumerate(objects, 1):
        offsets.append(len(out))
        out += b"%d 0 obj\n" % number + body + b"\nendobj\n"
    xref = len(out)
    out += b"xref\n0 %d\n0000000000 65535 f \n" % (len(objects) + 1)
    out += b"".join(b"%010d 00000 n \n" % offset for offset in offsets)
    out += b"trailer\n<< /Size %d /Root %d 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (len(objects) + 1, catalog_id, xref)
    with open(path, "wb") as file:
        file.write(out)


def main():
    output = sys.argv[1] if len(sys.argv) > 1 else "sample.pdf"
    write_pdf([landscape(), color_test(), report(), article(), sunset(), calendar()], output)
    print(output)


if __name__ == "__main__":
    main()
