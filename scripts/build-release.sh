#!/bin/bash
set -euo pipefail

# ctrl+v release builder
# Produces signed .app, Sparkle .zip, .dmg and checksums in dist/<version>/
#
# Optional env vars:
# - APPLE_DEVELOPER_ID_APPLICATION
# - APPLE_ID
# - APPLE_TEAM_ID
# - APPLE_APP_PASSWORD
# - SPARKLE_EDDSA_PRIVATE_KEY

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RESOURCES_DIR="${PROJECT_DIR}/Resources"
INFO_PLIST="${RESOURCES_DIR}/Info.plist"
ENTITLEMENTS="${RESOURCES_DIR}/InstantTranslator.entitlements"
BIN_NAME="InstantTranslator"
BUNDLE_NAME="ctrl+v.app"
SPARKLE_SIGN_BIN="${PROJECT_DIR}/.build/artifacts/sparkle/Sparkle/bin/sign_update"
ARM_BUILD_TRIPLE="${CTRLV_ARM_BUILD_TRIPLE:-arm64-apple-macosx14.0}"
X86_BUILD_TRIPLE="${CTRLV_X86_BUILD_TRIPLE:-x86_64-apple-macosx14.0}"

read_plist_value() {
    /usr/libexec/PlistBuddy -c "Print:${1}" "${INFO_PLIST}"
}

VERSION="${1:-$(read_plist_value CFBundleShortVersionString)}"
BUILD_NUMBER="${2:-$(read_plist_value CFBundleVersion)}"
DIST_DIR="${PROJECT_DIR}/dist/${VERSION}"
APP_BUNDLE="${DIST_DIR}/${BUNDLE_NAME}"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
ZIP_PATH="${DIST_DIR}/ctrlv-${VERSION}.zip"
DMG_PATH="${DIST_DIR}/ctrlv-${VERSION}.dmg"
CHECKSUMS_PATH="${DIST_DIR}/SHA256SUMS.txt"
SPARKLE_SIG_PATH="${DIST_DIR}/sparkle-signature.txt"
SPARKLE_FRAMEWORK_SOURCE="${PROJECT_DIR}/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
ARM_BINARY_PATH="${PROJECT_DIR}/.build/arm64-apple-macosx/release/${BIN_NAME}"
X86_BINARY_PATH="${PROJECT_DIR}/.build/x86_64-apple-macosx/release/${BIN_NAME}"
UNIVERSAL_BINARY_PATH="${DIST_DIR}/${BIN_NAME}-universal"

echo "==> Building release binaries (${VERSION}, build ${BUILD_NUMBER})"
cd "${PROJECT_DIR}"
swift build -c release --triple "${ARM_BUILD_TRIPLE}"
swift build -c release --triple "${X86_BUILD_TRIPLE}"

echo "==> Assembling app bundle"
rm -rf "${DIST_DIR}"
mkdir -p "${CONTENTS_DIR}/MacOS" "${CONTENTS_DIR}/Resources" "${CONTENTS_DIR}/Frameworks"

if [[ ! -f "${ARM_BINARY_PATH}" || ! -f "${X86_BINARY_PATH}" ]]; then
    echo "Missing architecture build outputs:"
    echo "  arm64: ${ARM_BINARY_PATH}"
    echo "  x86_64: ${X86_BINARY_PATH}"
    exit 1
fi

echo "==> Creating universal binary (arm64 + x86_64)"
lipo -create -output "${UNIVERSAL_BINARY_PATH}" "${ARM_BINARY_PATH}" "${X86_BINARY_PATH}"
UNIVERSAL_ARCHS="$(lipo -archs "${UNIVERSAL_BINARY_PATH}")"
echo "    Universal binary architectures: ${UNIVERSAL_ARCHS}"
if [[ "${UNIVERSAL_ARCHS}" != *"arm64"* || "${UNIVERSAL_ARCHS}" != *"x86_64"* ]]; then
    echo "Universal binary is missing required architectures"
    exit 1
fi

cp "${UNIVERSAL_BINARY_PATH}" "${CONTENTS_DIR}/MacOS/${BIN_NAME}"
rm -f "${UNIVERSAL_BINARY_PATH}"

cp "${INFO_PLIST}" "${CONTENTS_DIR}/Info.plist"
cp "${ENTITLEMENTS}" "${CONTENTS_DIR}/Resources/"

echo "==> Setting bundle version metadata"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "${CONTENTS_DIR}/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER}" "${CONTENTS_DIR}/Info.plist"

if [[ -d "${SPARKLE_FRAMEWORK_SOURCE}" ]]; then
    cp -R "${SPARKLE_FRAMEWORK_SOURCE}" "${CONTENTS_DIR}/Frameworks/"
fi

echo "==> Clearing extended attributes"
xattr -cr "${APP_BUNDLE}"

echo "==> Signing app bundle"
SIGN_IDENTITY="${APPLE_DEVELOPER_ID_APPLICATION:--}"
if [[ "${SIGN_IDENTITY}" == "-" ]]; then
    echo "    Using ad-hoc signing"
    if [[ -d "${CONTENTS_DIR}/Frameworks/Sparkle.framework" ]]; then
        codesign --force --deep --sign - "${CONTENTS_DIR}/Frameworks/Sparkle.framework"
    fi
    codesign --force --deep --sign - --entitlements "${ENTITLEMENTS}" "${APP_BUNDLE}"
else
    echo "    Using Developer ID signing: ${SIGN_IDENTITY}"
    if [[ -d "${CONTENTS_DIR}/Frameworks/Sparkle.framework" ]]; then
        codesign --force --deep --timestamp --options runtime --sign "${SIGN_IDENTITY}" "${CONTENTS_DIR}/Frameworks/Sparkle.framework"
    fi
    codesign --force --deep --timestamp --options runtime --sign "${SIGN_IDENTITY}" --entitlements "${ENTITLEMENTS}" "${APP_BUNDLE}"
fi

if [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" && "${SIGN_IDENTITY}" != "-" ]]; then
    echo "==> Notarizing app bundle"
    NOTARY_ZIP="${DIST_DIR}/notary-upload.zip"
    ditto -c -k --sequesterRsrc --keepParent "${APP_BUNDLE}" "${NOTARY_ZIP}"
    xcrun notarytool submit "${NOTARY_ZIP}" \
        --apple-id "${APPLE_ID}" \
        --team-id "${APPLE_TEAM_ID}" \
        --password "${APPLE_APP_PASSWORD}" \
        --wait
    xcrun stapler staple "${APP_BUNDLE}"
    rm -f "${NOTARY_ZIP}"
else
    echo "==> Skipping notarization (missing Apple credentials)"
fi

echo "==> Packaging zip for Sparkle"
ditto -c -k --sequesterRsrc --keepParent "${APP_BUNDLE}" "${ZIP_PATH}"

echo "==> Packaging DMG"
DMG_STAGING="${DIST_DIR}/dmg-staging"
rm -rf "${DMG_STAGING}"
mkdir -p "${DMG_STAGING}"
cp -R "${APP_BUNDLE}" "${DMG_STAGING}/"
hdiutil create -volname "ctrl+v" -srcfolder "${DMG_STAGING}" -ov -format UDZO "${DMG_PATH}"
rm -rf "${DMG_STAGING}"

echo "==> Generating checksums"
ZIP_SHA="$(shasum -a 256 "${ZIP_PATH}" | awk '{print $1}')"
DMG_SHA="$(shasum -a 256 "${DMG_PATH}" | awk '{print $1}')"
cat > "${CHECKSUMS_PATH}" <<EOF
${ZIP_SHA}  ctrlv-${VERSION}.zip
${DMG_SHA}  ctrlv-${VERSION}.dmg
EOF

if [[ -x "${SPARKLE_SIGN_BIN}" && -n "${SPARKLE_EDDSA_PRIVATE_KEY:-}" ]]; then
    echo "==> Generating Sparkle EdDSA signature"
    SPARKLE_SIGNATURE="$(
        printf '%s\n' "${SPARKLE_EDDSA_PRIVATE_KEY}" \
        | "${SPARKLE_SIGN_BIN}" --ed-key-file - -p "${ZIP_PATH}" \
        | tr -d '\n'
    )"
    printf '%s\n' "${SPARKLE_SIGNATURE}" > "${SPARKLE_SIG_PATH}"
else
    echo "==> Skipping Sparkle signature (missing sign_update or key)"
fi

cat <<EOF

Release artifacts:
  App: ${APP_BUNDLE}
  Zip: ${ZIP_PATH}
  DMG: ${DMG_PATH}
  Checksums: ${CHECKSUMS_PATH}
  Sparkle signature: ${SPARKLE_SIG_PATH}
EOF
