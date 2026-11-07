#!/bin/sh
# README ekran görüntülerini yeniden üretir: Debug derlemesini ScreenshotMode ile açar,
# örnek belgeyi yükler, pencereleri çizer ve screenshots/ klasörüne gölgeli olarak yazar.
#   Scripts/screenshots.sh            koyu görünüm
#   APPEARANCE=light Scripts/screenshots.sh
# Gerekenler: Xcode, Python 3 + Pillow. Durum kartı için CLP-300 bağlı ve açık olmalı.
# Yazıcıya hiçbir şey gönderilmez. Çalışan PrinterManager'ı önce kapatın.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

echo "Debug derleniyor..."
xcodebuild -project "$ROOT/PrinterManager.xcodeproj" -scheme PrinterManager \
    -configuration Debug -derivedDataPath "$WORK/dd" build >/dev/null

python3 "$ROOT/Scripts/sample-document.py" "$WORK/Örnek Belge.pdf" >/dev/null

echo "Pencereler çiziliyor..."
"$WORK/dd/Build/Products/Debug/PrinterManager.app/Contents/MacOS/PrinterManager" \
    -PMScreenshots "$WORK/raw" -PMSamplePDF "$WORK/Örnek Belge.pdf" \
    -PMAppearance "${APPEARANCE:-dark}" >/dev/null 2>&1

# Köşeleri yuvarla, gölge ekle
python3 - "$WORK/raw" "$ROOT/screenshots" <<'EOF'
import os
import sys
from PIL import Image, ImageDraw, ImageFilter

source, target = sys.argv[1:3]
os.makedirs(target, exist_ok=True)
for name in sorted(os.listdir(source)):
    window = Image.open(os.path.join(source, name)).convert("RGBA")
    radius, pad = 26, 80
    mask = Image.new("L", window.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, window.width - 1, window.height - 1), radius, fill=255)
    canvas = Image.new("RGBA", (window.width + pad * 2, window.height + pad * 2), (0, 0, 0, 0))
    shadow = Image.new("L", canvas.size, 0)
    ImageDraw.Draw(shadow).rounded_rectangle(
        (pad, pad + 18, pad + window.width, pad + window.height + 18), radius, fill=110)
    canvas.putalpha(shadow.filter(ImageFilter.GaussianBlur(28)))
    canvas.paste(window, (pad, pad), mask)
    canvas.save(os.path.join(target, name), optimize=True)
    print(os.path.join(target, name))
EOF
