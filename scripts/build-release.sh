#!/bin/bash
set -euo pipefail
export COPYFILE_DISABLE=1

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
ASSET_CATALOG="${RESOURCES_DIR}/Assets.xcassets"
BIN_NAME="InstantTranslator"
BUNDLE_NAME="ctrlv.app"
SPARKLE_SIGN_BIN="${PROJECT_DIR}/.build/artifacts/sparkle/Sparkle/bin/sign_update"
ARM_BUILD_TRIPLE="${CTRLV_ARM_BUILD_TRIPLE:-arm64-apple-macosx14.0}"
X86_BUILD_TRIPLE="${CTRLV_X86_BUILD_TRIPLE:-x86_64-apple-macosx14.0}"

read_plist_value() {
    /usr/libexec/PlistBuddy -c "Print:${1}" "${INFO_PLIST}"
}

clean_xattrs() {
    local target="$1"
    [[ -e "${target}" ]] || return 0

    # Remove known problematic metadata first (iCloud/FileProvider + Finder detritus).
    find "${target}" -print0 2>/dev/null | while IFS= read -r -d '' path; do
        xattr -d com.apple.FinderInfo "${path}" 2>/dev/null || true
        xattr -d com.apple.ResourceFork "${path}" 2>/dev/null || true
        xattr -d "com.apple.fileprovider.fpfs#P" "${path}" 2>/dev/null || true
    done

    xattr -cr "${target}" 2>/dev/null || true
    find "${target}" -exec xattr -c {} + 2>/dev/null || true
    find "${target}" -name '._*' -type f -delete 2>/dev/null || true
    dot_clean -m "${target}" 2>/dev/null || true
}

derive_build_number_from_version() {
    local version="$1"
    local major minor patch
    IFS='.' read -r major minor patch <<< "${version}"
    if [[ "${major}" =~ ^[0-9]+$ && "${minor}" =~ ^[0-9]+$ && "${patch}" =~ ^[0-9]+$ ]]; then
        echo $((major * 10000 + minor * 100 + patch))
    else
        read_plist_value CFBundleVersion
    fi
}

VERSION="${1:-$(read_plist_value CFBundleShortVersionString)}"
BUILD_NUMBER="${2:-$(derive_build_number_from_version "${VERSION}")}"
DIST_BASE_DIR="${CTRLV_DIST_DIR_BASE:-${PROJECT_DIR}/dist}"
DIST_DIR="${DIST_BASE_DIR}/${VERSION}"
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

# Ensure bundled frameworks resolve correctly at runtime.
if ! otool -l "${CONTENTS_DIR}/MacOS/${BIN_NAME}" | grep -q "@executable_path/../Frameworks"; then
    install_name_tool -add_rpath "@executable_path/../Frameworks" "${CONTENTS_DIR}/MacOS/${BIN_NAME}"
fi

ditto --noextattr --noqtn "${INFO_PLIST}" "${CONTENTS_DIR}/Info.plist"
ditto --noextattr --noqtn "${ENTITLEMENTS}" "${CONTENTS_DIR}/Resources/InstantTranslator.entitlements"

if [[ -d "${ASSET_CATALOG}" ]]; then
    echo "==> Compiling asset catalog"
    xcrun actool "${ASSET_CATALOG}" \
        --compile "${CONTENTS_DIR}/Resources" \
        --platform macosx \
        --minimum-deployment-target 14.0 \
        --app-icon AppIcon \
        --output-partial-info-plist "${DIST_DIR}/assetcatalog-info.plist" >/dev/null
fi

echo "==> Setting bundle version metadata"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "${CONTENTS_DIR}/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER}" "${CONTENTS_DIR}/Info.plist"

if [[ -d "${SPARKLE_FRAMEWORK_SOURCE}" ]]; then
    clean_xattrs "${SPARKLE_FRAMEWORK_SOURCE}"
    ditto --noextattr --noqtn --norsrc "${SPARKLE_FRAMEWORK_SOURCE}" "${CONTENTS_DIR}/Frameworks/Sparkle.framework"
fi

echo "==> Clearing extended attributes"
clean_xattrs "${APP_BUNDLE}"

echo "==> Signing app bundle"
SIGN_IDENTITY="${APPLE_DEVELOPER_ID_APPLICATION:--}"
if [[ "${SIGN_IDENTITY}" == "-" ]]; then
    echo "    Using ad-hoc signing"
    if [[ -d "${CONTENTS_DIR}/Frameworks/Sparkle.framework" ]]; then
        clean_xattrs "${CONTENTS_DIR}/Frameworks/Sparkle.framework"
        codesign --force --deep --sign - "${CONTENTS_DIR}/Frameworks/Sparkle.framework"
    fi
    clean_xattrs "${APP_BUNDLE}"
    codesign --force --deep --sign - --entitlements "${ENTITLEMENTS}" "${APP_BUNDLE}"
else
    echo "    Using Developer ID signing: ${SIGN_IDENTITY}"
    if [[ -d "${CONTENTS_DIR}/Frameworks/Sparkle.framework" ]]; then
        clean_xattrs "${CONTENTS_DIR}/Frameworks/Sparkle.framework"
        codesign --force --deep --timestamp --options runtime --sign "${SIGN_IDENTITY}" "${CONTENTS_DIR}/Frameworks/Sparkle.framework"
    fi
    clean_xattrs "${APP_BUNDLE}"
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
DMG_BACKGROUND="${DIST_DIR}/dmg-background.png"
RW_DMG_PATH="${DIST_DIR}/ctrlv-${VERSION}-rw.dmg"
DMG_MOUNT_PATH="${DIST_DIR}/dmg-mount"
rm -rf "${DMG_STAGING}"
mkdir -p "${DMG_STAGING}"
ditto --noextattr --noqtn --norsrc "${APP_BUNDLE}" "${DMG_STAGING}/ctrlv.app"
ln -s /Applications "${DMG_STAGING}/Applications"

if swift "${PROJECT_DIR}/scripts/generate-dmg-background.swift" "${DMG_BACKGROUND}" >/dev/null 2>&1; then
    mkdir -p "${DMG_STAGING}/.background"
    cp -f "${DMG_BACKGROUND}" "${DMG_STAGING}/.background/background.png"
fi

rm -f "${RW_DMG_PATH}"
if mount | grep -Fq "${DMG_MOUNT_PATH}"; then
    hdiutil detach "${DMG_MOUNT_PATH}" -quiet || hdiutil detach -force "${DMG_MOUNT_PATH}" -quiet || true
fi
rm -rf "${DMG_MOUNT_PATH}"
mkdir -p "${DMG_MOUNT_PATH}"

if hdiutil create -volname "ctrl+v" -srcfolder "${DMG_STAGING}" -ov -format UDRW "${RW_DMG_PATH}"; then
    ATTACH_OUTPUT="$(hdiutil attach -readwrite -noverify -noautoopen "${RW_DMG_PATH}" -mountpoint "${DMG_MOUNT_PATH}" 2>/dev/null || true)"
    DEVICE="$(printf '%s\n' "${ATTACH_OUTPUT}" | awk -v mp="${DMG_MOUNT_PATH}" '$0 ~ mp {print $1; exit}')"
    if [[ -z "${DEVICE}" ]]; then
        DEVICE="$(printf '%s\n' "${ATTACH_OUTPUT}" | awk '/^\/dev\/disk/ {last=$1} END{print last}')"
    fi

    if [[ -n "${DEVICE}" ]]; then
        osascript >/dev/null 2>&1 <<EOF || true
tell application "Finder"
    tell disk "ctrl+v"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {120, 120, 900, 600}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 128
        set text size of viewOptions to 14
        try
            set background picture of viewOptions to file ".background:background.png"
        end try
        set position of item "ctrlv.app" of container window to {190, 220}
        set position of item "Applications" of container window to {520, 220}
        close
        open
        update without registering applications
        delay 1
    end tell
end tell
EOF
        sync
    fi

    if mount | grep -Fq "${DMG_MOUNT_PATH}"; then
        hdiutil detach "${DMG_MOUNT_PATH}" -quiet || hdiutil detach -force "${DMG_MOUNT_PATH}" -quiet || true
    fi
    if [[ -n "${DEVICE}" ]]; then
        hdiutil detach "${DEVICE}" -quiet || hdiutil detach -force "${DEVICE}" -quiet || true
    fi
    sync
    sleep 1

    hdiutil convert "${RW_DMG_PATH}" -ov -format UDZO -imagekey zlib-level=9 -o "${DMG_PATH}"
    rm -f "${RW_DMG_PATH}"
else
    hdiutil create -volname "ctrl+v" -srcfolder "${DMG_STAGING}" -ov -format UDZO "${DMG_PATH}"
fi

rm -rf "${DMG_MOUNT_PATH}"
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
