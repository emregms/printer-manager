#!/bin/sh
# Xcode "Bundle Ghostscript" adımı: build-gs.sh'nin derleyip repoya koyduğu gs'yi
# uygulama paketine yardımcı araç olarak koyar (Contents/Helpers/gs), AGPL metnini ve
# içindeki kütüphanelerin lisanslarını Resources'a kopyalar ve uygulamanın kimliğiyle
# imzalar. Ghostscript'i burada derlemez (birkaç dakika sürer); yalnız kopyalar.
set -eu

SRC="${SRCROOT}/ThirdParty/ghostscript"
HELPERS="${TARGET_BUILD_DIR}/${CONTENTS_FOLDER_PATH}/Helpers"
RESOURCES="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"

if [ ! -f "${SRC}/bin/gs" ]; then
    echo "error: ThirdParty/ghostscript/bin/gs yok; önce ThirdParty/ghostscript/build-gs.sh çalıştırın" >&2
    exit 1
fi
# Repodaki ikili, kaydedilen sağlama toplamıyla aynı olmalı
(cd "${SRC}" && shasum -a 256 -c --quiet SHA256SUMS)
for arch in ${ARCHS}; do
    lipo "${SRC}/bin/gs" -verify_arch "${arch}"
done

mkdir -p "${HELPERS}" "${RESOURCES}"
rm -f "${HELPERS}/gs"
cp "${SRC}/bin/gs" "${HELPERS}/gs"
cp "${SRC}/COPYING" "${RESOURCES}/ghostscript-COPYING.txt"
cp "${SRC}/THIRD-PARTY.txt" "${RESOURCES}/ghostscript-THIRD-PARTY.txt"

# Uygulama sonradan imzalanırken iç içe kodun imzalı olması gerekiyor.
if [ "${CODE_SIGNING_ALLOWED:-NO}" = "YES" ] && [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]; then
    codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY}" \
        --options runtime --timestamp=none "${HELPERS}/gs"
fi
