#!/bin/bash
set -euo pipefail

# Publishes an existing local release from dist/<version>/ into docs/ and updates appcast/latest.json.
#
# Usage:
#   ./scripts/publish-release-to-docs.sh <version> [download-url-prefix] [release-notes-url-prefix]
#
# Optional env vars:
# - SPARKLE_EDDSA_PRIVATE_KEY (recommended for signed appcast entries)

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:?Version is required (eg 1.0.1)}"
DOWNLOAD_URL_PREFIX="${2:-https://control-v.info/downloads}"
RELEASE_NOTES_URL_PREFIX="${3:-https://control-v.info/release-notes}"

DIST_DIR="${PROJECT_DIR}/dist/${VERSION}"
DOCS_DIR="${PROJECT_DIR}/docs"
DOCS_DOWNLOADS_DIR="${DOCS_DIR}/downloads"
DOCS_NOTES_DIR="${DOCS_DIR}/release-notes"
CHECKSUMS_FILE="${DIST_DIR}/SHA256SUMS.txt"
NOTES_FILE="${DIST_DIR}/release-notes.md"
DMG_FILE="${DIST_DIR}/ctrlv-${VERSION}.dmg"
ZIP_FILE="${DIST_DIR}/ctrlv-${VERSION}.zip"

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

if [[ ! -f "${ZIP_FILE}" || ! -f "${DMG_FILE}" || ! -f "${CHECKSUMS_FILE}" ]]; then
    echo "Missing release artifacts in ${DIST_DIR}"
    echo "Expected:"
    echo "  - $(basename "${ZIP_FILE}")"
    echo "  - $(basename "${DMG_FILE}")"
    echo "  - $(basename "${CHECKSUMS_FILE}")"
    exit 1
fi

if [[ ! -f "${NOTES_FILE}" ]]; then
    cat > "${NOTES_FILE}" <<EOF
# ctrl+v ${VERSION}

- Improvements and fixes.
EOF
fi

echo "==> Generating appcast"
"${PROJECT_DIR}/scripts/generate-appcast.sh" \
    "${VERSION}" \
    "${DOWNLOAD_URL_PREFIX}" \
    "${RELEASE_NOTES_URL_PREFIX}"

echo "==> Copying artifacts to docs/"
mkdir -p "${DOCS_DOWNLOADS_DIR}" "${DOCS_NOTES_DIR}"
cp -f "${DMG_FILE}" "${DOCS_DOWNLOADS_DIR}/"
cp -f "${ZIP_FILE}" "${DOCS_DOWNLOADS_DIR}/"
cp -f "${NOTES_FILE}" "${DOCS_NOTES_DIR}/ctrlv-${VERSION}.md"
cp -f "${CHECKSUMS_FILE}" "${DOCS_DIR}/SHA256SUMS.txt"

ZIP_SHA="$(awk '/ctrlv-.*\.zip/{print $1}' "${CHECKSUMS_FILE}" | head -n 1)"
DMG_SHA="$(awk '/ctrlv-.*\.dmg/{print $1}' "${CHECKSUMS_FILE}" | head -n 1)"

cat > "${DOCS_DIR}/latest.json" <<EOF
{
  "version": "${VERSION}",
  "dmg_url": "${DOWNLOAD_URL_PREFIX}ctrlv-${VERSION}.dmg",
  "zip_url": "${DOWNLOAD_URL_PREFIX}ctrlv-${VERSION}.zip",
  "dmg_sha256": "${DMG_SHA}",
  "zip_sha256": "${ZIP_SHA}"
}
EOF

cat <<EOF

Published local release to docs:
  - ${DOCS_DOWNLOADS_DIR}/ctrlv-${VERSION}.dmg
  - ${DOCS_DOWNLOADS_DIR}/ctrlv-${VERSION}.zip
  - ${DOCS_DIR}/updates/appcast.xml
  - ${DOCS_DIR}/latest.json
EOF
