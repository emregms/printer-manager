#!/bin/sh
# Xcode "Build helpers" adımı: uygulamanın yardımcı araçlarını paketin
# Contents/Helpers klasörüne derler ve uygulamanın kimliğiyle imzalar:
#   cups-jobs       başka uygulamalardan gelen işleri alır (libcups)
#   clp300-status   yazıcının durumunu ve tonerlerini USB'den okur (IOKit)
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

# shellcheck disable=SC2086
xcrun clang ${ARCH_FLAGS} -mmacosx-version-min="${MACOSX_DEPLOYMENT_TARGET}" \
    -O2 -Wall \
    -o "${HELPERS}/clp300-status" "${SRC}/clp300-status.c" \
    -framework IOKit -framework CoreFoundation

if [ "${CODE_SIGNING_ALLOWED:-NO}" = "YES" ] && [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]; then
    for helper in cups-jobs clp300-status; do
        codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY}" \
            --options runtime --timestamp=none "${HELPERS}/${helper}"
    done
fi
