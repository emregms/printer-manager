#!/bin/sh
# Ghostscript'i kaynaktan, yalnız uygulamanın kullandığı aygıtlarla derler ve
# ThirdParty/ghostscript/bin/gs olarak saklar (arm64 + x86_64, tek dosya).
# Kaynaklar (init dosyaları, yazı tipleri, ICC profilleri) ikilinin içine gömülür
# (COMPILE_INITS=1); Homebrew'a ya da başka bir kütüphaneye bağımlılığı yoktur.
#
#   ThirdParty/ghostscript/build-gs.sh [ghostscript-10.08.0.tar.xz]
#
# Arşiv verilmezse Artifex'in GitHub sürümünden indirilir. SHA-512 her durumda
# Artifex'in yayımladığı değerle karşılaştırılır. Apple Silicon'da x86_64 kısmı
# çapraz derlenir (yardımcı araçlar yerel derlenir). Süre: ~3-5 dakika.
# Xcode bu betiği çalıştırmaz; yalnız sonucu pakete koyar (bundle-helper.sh).
set -eu

VERSION=10.08.0
URL="https://github.com/ArtifexSoftware/ghostpdl-downloads/releases/download/gs10080/ghostscript-${VERSION}.tar.xz"
SHA512=8006e2a32d03759a905b9548bdd83d4563173041006750e17e428b9eea24ad519aa4452ceecd7c073d3c420a68bf1b07ccc9e0533b1a05935f6b39ea8d9ce875
# Uygulamanın çağırdığı aygıtlar (Services/QPDLDriver.swift)
DEVICES=bitcmyk,pbmraw,pgmraw,ppmraw
MACOS_MIN=13.0
ARCHS="arm64 x86_64"
# %rom% dosya sisteminin tarihi: sürümün yayın günü (2026-09-08), derleme anı değil
export SOURCE_DATE_EPOCH=1788825600

HERE=$(cd "$(dirname "$0")" && pwd)
OUT="${HERE}/bin"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

if [ $# -ge 1 ]; then
    TARBALL=$1
else
    TARBALL="${WORK}/ghostscript-${VERSION}.tar.xz"
    echo "İndiriliyor: ${URL}"
    curl -fL --progress-bar -o "$TARBALL" "$URL"
fi
echo "${SHA512}  ${TARBALL}" | shasum -a 512 -c -

triple() {
    case $1 in
        arm64) echo aarch64-apple-darwin ;;
        x86_64) echo x86_64-apple-darwin ;;
    esac
}
BUILD=$(triple "$(uname -m)")
JOBS=$(sysctl -n hw.ncpu)

for arch in $ARCHS; do
    echo "Derleniyor: ${arch}"
    mkdir "${WORK}/${arch}"
    tar -xJf "$TARBALL" -C "${WORK}/${arch}"
    src="${WORK}/${arch}/ghostscript-${VERSION}"
    (
        cd "$src"
        # Var olmayan önek: Mac'te kurulu başka bir Ghostscript'in dosyalarını okumasın.
        # -ffile-prefix-map: geçici klasörün yolu ikiliye girmesin (tekrarlanabilir derleme).
        ./configure --quiet \
            --host="$(triple "$arch")" --build="$BUILD" \
            --prefix=/nonexistent/printermanager-ghostscript \
            CC="xcrun clang -arch ${arch} -mmacosx-version-min=${MACOS_MIN}" \
            CCAUX="xcrun clang" \
            CFLAGS="-ffile-prefix-map=${src}=ghostscript-${VERSION}" \
            --with-drivers="$DEVICES" \
            --disable-contrib --disable-cups --disable-dbus --disable-fontconfig --disable-gtk \
            --without-x --without-tesseract --without-libidn --without-libpaper --without-libtiff \
            --without-pdftoraster --without-ijs --without-urf --without-so --with-libiconv=no \
            --enable-mkromfs-quiet
        # PDF yorumlayıcısı RC4 şifreli PDF'ler için sarc4'ü kullanıyor ama pdf.mak onu
        # istemiyor; normalde pdfwrite ile gelir. pdfwrite'sız derlemede bağlama hatası verir.
        sed -i '' 's/^FEATURE_DEVS=/FEATURE_DEVS=$(GLD)sarc4.dev /' Makefile
        grep -q '^FEATURE_DEVS=$(GLD)sarc4.dev ' Makefile
        make -j"$JOBS" >"${WORK}/${arch}.log" 2>&1 || { tail -40 "${WORK}/${arch}.log"; exit 1; }
    )
    cp "${src}/bin/gs" "${WORK}/gs-${arch}"
    strip "${WORK}/gs-${arch}"
done

mkdir -p "$OUT"
# shellcheck disable=SC2086
lipo -create $(for arch in $ARCHS; do echo "${WORK}/gs-${arch}"; done) -output "${OUT}/gs"

# Lisanslar: Ghostscript'in AGPL metni ve ikiliye gömülen kütüphanelerin/yazı tiplerinin
# bildirimleri, kaynak arşivindeki dosyalardan
src="${WORK}/arm64/ghostscript-${VERSION}"
cp "${src}/doc/COPYING" "${HERE}/COPYING"
section() {
    printf '\n==============================================================================\n'
    printf '%s  (ghostscript-%s/%s)\n' "$1" "$VERSION" "$2"
    printf '==============================================================================\n\n'
    cat "${src}/$2"
}
{
    echo "Ghostscript ${VERSION} ve içine derlenen bileşenlerin lisansları."
    echo "Licenses of Ghostscript ${VERSION} and the components compiled into it."
    echo "Ghostscript: GNU AGPL v3 (ghostscript-COPYING.txt). Source: ${URL}"
    section "Ghostscript" LICENSE
    section "FreeType" freetype/docs/FTL.TXT
    printf '\n==============================================================================\n'
    printf 'IJG libjpeg  (ghostscript-%s/jpeg/README, LEGAL ISSUES)\n' "$VERSION"
    printf '==============================================================================\n\n'
    echo "This software is based in part on the work of the Independent JPEG Group."
    echo
    sed -n '/^LEGAL ISSUES$/,/^REFERENCES$/p' "${src}/jpeg/README" | sed '$d'
    section "Little CMS (lcms2mt)" lcms2mt/COPYING
    section "libpng" libpng/LICENSE
    section "zlib" zlib/LICENSE
    section "OpenJPEG" openjpeg/LICENSE
    section "jbig2dec" jbig2dec/LICENSE
    section "Brotli" brotli/LICENSE
    section "Droid Sans Fallback (Resource/CIDFSubst)" DroidSansFallback.NOTICE
} > "${HERE}/THIRD-PARTY.txt"

# Yalnız sistem kütüphaneleri
if otool -L "${OUT}/gs" | tail -n +2 | grep -v -E '^[[:space:]]+/(usr/lib|System/Library)/' | grep -v ':$'; then
    echo "Hata: gs sistem dışı bir kütüphaneye bağlı" >&2
    exit 1
fi
for arch in $ARCHS; do
    lipo "${OUT}/gs" -verify_arch "$arch"
done
"${OUT}/gs" --version

(cd "$HERE" && shasum -a 256 bin/gs COPYING THIRD-PARTY.txt > SHA256SUMS)
cat "${HERE}/SHA256SUMS"
ls -l "${OUT}/gs"
