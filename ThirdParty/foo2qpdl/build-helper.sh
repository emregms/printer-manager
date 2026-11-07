#!/bin/sh
# Xcode "Build foo2qpdl" adımı: foo2qpdl'yi uygulama paketine yardımcı araç
# olarak derler (Contents/Helpers/foo2qpdl), GPL metnini Resources'a koyar ve
# uygulamanın kimliğiyle imzalar. Bayraklar upstream Makefile'daki gibi: -O2 -Wall.
set -eu

SRC="${SRCROOT}/ThirdParty/foo2qpdl"
HELPERS="${TARGET_BUILD_DIR}/${CONTENTS_FOLDER_PATH}/Helpers"
RESOURCES="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"

ARCH_FLAGS=""
for arch in ${ARCHS}; do
    ARCH_FLAGS="${ARCH_FLAGS} -arch ${arch}"
done

mkdir -p "${HELPERS}" "${RESOURCES}"

# shellcheck disable=SC2086
xcrun clang ${ARCH_FLAGS} -mmacosx-version-min="${MACOSX_DEPLOYMENT_TARGET}" \
    -O2 -Wall -Wno-unused-but-set-variable \
    -o "${HELPERS}/foo2qpdl" \
    "${SRC}/foo2qpdl.c" "${SRC}/jbig.c" "${SRC}/jbig_ar.c"

cp "${SRC}/COPYING" "${RESOURCES}/foo2qpdl-COPYING.txt"

# Uygulama sonradan imzalanırken iç içe kodun imzalı olması gerekiyor.
if [ "${CODE_SIGNING_ALLOWED:-NO}" = "YES" ] && [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]; then
    codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY}" \
        --options runtime --timestamp=none "${HELPERS}/foo2qpdl"
fi
