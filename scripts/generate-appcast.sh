#!/bin/bash
set -euo pipefail

# Generates/updates Sparkle appcast feed from dist artifacts.
#
# Usage:
#   scripts/generate-appcast.sh <version> [download-url-prefix] [release-notes-url-prefix]
#
# Optional env vars:
# - SPARKLE_EDDSA_PRIVATE_KEY

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:?Version is required (eg 1.0.0)}"
DOWNLOAD_URL_PREFIX="${2:-https://github.com/juanda89/ctrlv/releases/latest/download}"
RELEASE_NOTES_URL_PREFIX="${3:-https://github.com/juanda89/ctrlv/releases/latest/download}"
DIST_DIR="${PROJECT_DIR}/dist/${VERSION}"
SOURCE_ZIP="${DIST_DIR}/ctrlv-${VERSION}.zip"
SOURCE_NOTES="${DIST_DIR}/release-notes.md"
UPDATES_DIR="${PROJECT_DIR}/updates/stable"
DOCS_UPDATES_DIR="${PROJECT_DIR}/docs/updates"
GENERATE_BIN="${PROJECT_DIR}/.build/artifacts/sparkle/Sparkle/bin/generate_appcast"
TMP_FEED_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ctrlv-appcast.XXXXXX")"

cleanup() {
    rm -rf "${TMP_FEED_DIR}"
}
trap cleanup EXIT

ensure_trailing_slash() {
    local value="$1"
    if [[ "${value}" == */ ]]; then
        printf '%s' "${value}"
    else
        printf '%s/' "${value}"
    fi
}

DOWNLOAD_URL_PREFIX="$(ensure_trailing_slash "${DOWNLOAD_URL_PREFIX}")"
RELEASE_NOTES_URL_PREFIX="$(ensure_trailing_slash "${RELEASE_NOTES_URL_PREFIX}")"

if [[ ! -x "${GENERATE_BIN}" ]]; then
    echo "generate_appcast not found at ${GENERATE_BIN}"
    exit 1
fi

if [[ ! -f "${SOURCE_ZIP}" ]]; then
    echo "Missing archive: ${SOURCE_ZIP}"
    exit 1
fi

mkdir -p "${UPDATES_DIR}" "${DOCS_UPDATES_DIR}"
rm -f "${UPDATES_DIR}/appcast.xml" "${DOCS_UPDATES_DIR}/appcast.xml"
cp -f "${SOURCE_ZIP}" "${TMP_FEED_DIR}/"

if [[ -f "${SOURCE_NOTES}" ]]; then
    cp -f "${SOURCE_NOTES}" "${TMP_FEED_DIR}/ctrlv-${VERSION}.md"
fi

echo "==> Generating appcast from ${SOURCE_ZIP}"
if [[ -n "${SPARKLE_EDDSA_PRIVATE_KEY:-}" ]]; then
    printf '%s\n' "${SPARKLE_EDDSA_PRIVATE_KEY}" | "${GENERATE_BIN}" \
        --ed-key-file - \
        --download-url-prefix "${DOWNLOAD_URL_PREFIX}" \
        --release-notes-url-prefix "${RELEASE_NOTES_URL_PREFIX}" \
        --maximum-deltas 0 \
        -o "${UPDATES_DIR}/appcast.xml" \
        "${TMP_FEED_DIR}"
else
    "${GENERATE_BIN}" \
        --download-url-prefix "${DOWNLOAD_URL_PREFIX}" \
        --release-notes-url-prefix "${RELEASE_NOTES_URL_PREFIX}" \
        --maximum-deltas 0 \
        -o "${UPDATES_DIR}/appcast.xml" \
        "${TMP_FEED_DIR}"
fi

cp -f "${SOURCE_ZIP}" "${UPDATES_DIR}/"
if [[ -f "${SOURCE_NOTES}" ]]; then
    cp -f "${SOURCE_NOTES}" "${UPDATES_DIR}/ctrlv-${VERSION}.md"
fi

cp -f "${UPDATES_DIR}/appcast.xml" "${DOCS_UPDATES_DIR}/appcast.xml"

echo "Appcast updated:"
echo "  ${UPDATES_DIR}/appcast.xml"
echo "  ${DOCS_UPDATES_DIR}/appcast.xml"
