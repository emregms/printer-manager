#!/bin/sh
# Dağıtım DMG'si: Release'i (Intel + Apple Silicon) temiz derler; içine uygulamayı,
# Uygulamalar kısayolunu ve kısa kurulum rehberini koyar.
#   Scripts/make-dmg.sh   →   build/PrinterManager-v<sürüm>.dmg
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
VERSION=$(sed -n 's/.*MARKETING_VERSION = \(.*\);/\1/p' "$ROOT/PrinterManager.xcodeproj/project.pbxproj" | head -1)
DMG="$ROOT/build/PrinterManager-v$VERSION.dmg"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

echo "PrinterManager $VERSION derleniyor (Release)..."
xcodebuild -project "$ROOT/PrinterManager.xcodeproj" -scheme PrinterManager \
    -configuration Release -derivedDataPath "$WORK/dd" \
    -destination "generic/platform=macOS" clean build >/dev/null

APP="$WORK/dd/Build/Products/Release/PrinterManager.app"
codesign --verify --deep --strict "$APP"
for binary in "$APP/Contents/MacOS/PrinterManager" "$APP"/Contents/Helpers/*; do
    lipo "$binary" -verify_arch arm64
    lipo "$binary" -verify_arch x86_64
done

STAGE="$WORK/dmg"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/PrinterManager.app"
ln -s /Applications "$STAGE/Applications"

cat > "$STAGE/Kurulum - Install.txt" <<EOF
PrinterManager $VERSION — Samsung CLP-300 için macOS sürücüsü ve yazdırma uygulaması

KURULUM
1. PrinterManager'ı yandaki Applications (Uygulamalar) klasörüne sürükleyin.
2. Uygulama Apple tarafından imzalı değil. İlk açılıştan önce Terminal'de bir kez:
       xattr -cr /Applications/PrinterManager.app
   (Ya da açmayı deneyin, sonra Sistem Ayarları > Gizlilik ve Güvenlik > "Yine de Aç".)
3. CLP-300'ü USB ile bağlayıp açın, sonra PrinterManager'ı açın.
4. Kurulum Yardımcısı kendiliğinden açılır; adımları sırayla yapın:
   - Ghostscript'i kurun (tek düğme; Homebrew yoksa onu da kurar).
   - "Sürücüyü Kur ve Yazıcıyı Ekle" deyin (Mac şifreniz sorulur).
   Samsung'un eski sürücüsü gerekmez.

Ayrıntılar ve sorun giderme: https://github.com/emregms/printer-manager

------------------------------------------------------------

PrinterManager $VERSION — macOS driver and printing app for the Samsung CLP-300

INSTALL
1. Drag PrinterManager to the Applications folder next to it.
2. The app is not signed by Apple. Before the first launch, run once in Terminal:
       xattr -cr /Applications/PrinterManager.app
   (Or try to open it, then System Settings > Privacy & Security > "Open Anyway".)
3. Connect the CLP-300 over USB and turn it on, then open PrinterManager.
4. The Setup Assistant opens by itself; follow the steps in order:
   - Install Ghostscript (one button; installs Homebrew too if missing).
   - Click "Sürücüyü Kur ve Yazıcıyı Ekle" (install driver and add printer;
     asks for your Mac password).
   Samsung's old driver is not needed.

Details and troubleshooting: https://github.com/emregms/printer-manager/blob/main/README_EN.md
EOF

mkdir -p "$ROOT/build"
rm -f "$DMG"
hdiutil create -quiet -volname "PrinterManager $VERSION" -srcfolder "$STAGE" \
    -fs HFS+ -format UDZO -imagekey zlib-level=9 "$DMG"
hdiutil verify -quiet "$DMG"

echo "$DMG"
shasum -a 256 "$DMG"
