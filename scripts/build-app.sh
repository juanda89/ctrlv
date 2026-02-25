#!/bin/bash
set -euo pipefail

# InstantTranslator — Build .app bundle from SPM
# Usage: bash scripts/build-app.sh

APP_NAME="InstantTranslator"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${PROJECT_DIR}/build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS="${APP_BUNDLE}/Contents"

echo "==> Building ${APP_NAME} (release)..."
cd "${PROJECT_DIR}"
swift build -c release

echo "==> Assembling .app bundle..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${CONTENTS}/MacOS"
mkdir -p "${CONTENTS}/Resources"

# Copy binary
cp ".build/release/${APP_NAME}" "${CONTENTS}/MacOS/"

# Copy Info.plist
cp "Resources/Info.plist" "${CONTENTS}/"

# Copy entitlements (for reference, used during codesign)
cp "Resources/${APP_NAME}.entitlements" "${CONTENTS}/Resources/"

echo "==> Signing (ad-hoc for local testing)..."
codesign --force --sign - \
    --entitlements "Resources/${APP_NAME}.entitlements" \
    --deep \
    "${APP_BUNDLE}"

echo ""
echo "================================================"
echo "  Build complete!"
echo "  ${APP_BUNDLE}"
echo ""
echo "  Run with:  open ${APP_BUNDLE}"
echo "================================================"
