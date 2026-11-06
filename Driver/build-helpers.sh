#!/bin/sh
# Xcode "Build cups-jobs" adımı: CUPS iş yardımcısını uygulama paketine
# derler (Contents/Helpers/cups-jobs) ve uygulamanın kimliğiyle imzalar.
set -eu

SRC="${SRCROOT}/Driver"
HELPERS="${TARGET_BUILD_DIR}/${CONTENTS_FOLDER_PATH}/Helpers"

ARCH_FLAGS=""
for arch in ${ARCHS}; do
    ARCH_FLAGS="${ARCH_FLAGS} -arch ${arch}"
done

mkdir -p "${HELPERS}"

# libcups'ın iş API'si macOS'ta "deprecated" işaretli ama destekleniyor
# shellcheck disable=SC2086
xcrun clang ${ARCH_FLAGS} -mmacosx-version-min="${MACOSX_DEPLOYMENT_TARGET}" \
    -O2 -Wall -Wno-deprecated-declarations \
    -o "${HELPERS}/cups-jobs" "${SRC}/cups-jobs.c" -lcups

if [ "${CODE_SIGNING_ALLOWED:-NO}" = "YES" ] && [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]; then
    codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY}" \
        --options runtime --timestamp=none "${HELPERS}/cups-jobs"
fi
