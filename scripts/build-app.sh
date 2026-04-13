#!/bin/bash
set -euo pipefail

# InstantTranslator — Build .app bundle from SPM
# Usage: bash scripts/build-app.sh

APP_NAME="InstantTranslator"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${PROJECT_DIR}/build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS="${APP_BUNDLE}/Contents"
ASSET_CATALOG="${PROJECT_DIR}/Resources/Assets.xcassets"

echo "==> Building ${APP_NAME} (release)..."
cd "${PROJECT_DIR}"
swift build -c release

echo "==> Assembling .app bundle..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${CONTENTS}/MacOS"
mkdir -p "${CONTENTS}/Resources"
mkdir -p "${CONTENTS}/Frameworks"

# Copy binary
cp ".build/release/${APP_NAME}" "${CONTENTS}/MacOS/"

# Copy dynamic frameworks produced by SwiftPM (e.g. Sparkle.framework).
if compgen -G ".build/release/*.framework" > /dev/null; then
    for framework in .build/release/*.framework; do
        cp -R "${framework}" "${CONTENTS}/Frameworks/"
    done
fi

# Ensure bundled frameworks resolve correctly at runtime.
if ! otool -l "${CONTENTS}/MacOS/${APP_NAME}" | grep -q "@executable_path/../Frameworks"; then
    install_name_tool -add_rpath "@executable_path/../Frameworks" "${CONTENTS}/MacOS/${APP_NAME}"
fi

# Copy Info.plist
cp "Resources/Info.plist" "${CONTENTS}/"

# Copy entitlements (for reference, used during codesign)
cp "Resources/${APP_NAME}.entitlements" "${CONTENTS}/Resources/"

if [[ -d "${ASSET_CATALOG}" ]]; then
    echo "==> Compiling asset catalog..."
    xcrun actool "${ASSET_CATALOG}" \
        --compile "${CONTENTS}/Resources" \
        --platform macosx \
        --minimum-deployment-target 14.0 \
        --app-icon AppIcon \
        --output-partial-info-plist "${BUILD_DIR}/assetcatalog-info.plist" >/dev/null
fi

SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application: Viko Holdings LLC (5ZFYF422LX)}"
echo "==> Signing with: ${SIGN_IDENTITY}..."
xattr -cr "${APP_BUNDLE}" || true

# Sign embedded frameworks first, then the main bundle.
if compgen -G "${CONTENTS}/Frameworks/*.framework" > /dev/null; then
    for framework in "${CONTENTS}"/Frameworks/*.framework; do
        codesign --force --sign "${SIGN_IDENTITY}" \
            --options runtime \
            "${framework}"
    done
fi

codesign --force --sign "${SIGN_IDENTITY}" \
    --entitlements "Resources/${APP_NAME}.entitlements" \
    --options runtime \
    "${APP_BUNDLE}"

echo ""
echo "================================================"
echo "  Build complete!"
echo "  ${APP_BUNDLE}"
echo ""
echo "  Run with:  open ${APP_BUNDLE}"
echo "================================================"
