#!/bin/bash
# Archive the iOS app and upload it to App Store Connect without opening Xcode.
#
#   bash scripts/ios-upload.sh            # uses the build number in iOS/project.yml
#   bash scripts/ios-upload.sh --bump     # increments it first, then uploads
#
# Signing is deliberately manual: the team's App Store Connect API key is an App
# Manager key and Apple refuses cloud signing for it ("Cloud signing permission
# error"), so Xcode cannot mint profiles on the fly. Instead the distribution
# certificate lives in a dedicated keychain and the four App Store profiles are
# created through the API by --refresh-profiles.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IOS="$REPO/iOS"
KEY_ID="${ASC_KEY_ID:-7325UTJ2UZ}"
ISSUER="${ASC_ISSUER:-425dc43b-2d68-4902-8a14-6935a90efa9a}"
KEY_PATH="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${KEY_ID}.p8}"
KEYCHAIN="$HOME/Library/Keychains/controlv-signing.keychain-db"
KEYCHAIN_PASS_FILE="$HOME/.config/ctrlv/signing-keychain-password"
WORK="${CTRLV_IOS_WORK:-$HOME/Library/Developer/Xcode/Archives/ctrlv-upload}"

bump=0
for arg in "$@"; do [ "$arg" = "--bump" ] && bump=1; done

[ -f "$KEY_PATH" ] || { echo "error: missing App Store Connect key at $KEY_PATH" >&2; exit 1; }

if [ "$bump" = "1" ]; then
  current=$(grep -E '^\s+CURRENT_PROJECT_VERSION:' "$IOS/project.yml" | head -1 | tr -dc '0-9')
  next=$((current + 1))
  /usr/bin/sed -i '' -E "s/(CURRENT_PROJECT_VERSION: )\"$current\"/\1\"$next\"/" "$IOS/project.yml"
  echo "build $current -> $next"
fi
version=$(grep -E '^\s+MARKETING_VERSION:' "$IOS/project.yml" | head -1 | cut -d'"' -f2)
build=$(grep -E '^\s+CURRENT_PROJECT_VERSION:' "$IOS/project.yml" | head -1 | tr -dc '0-9')

# The signing identity lives outside the login keychain so no password prompt
# can block an unattended upload.
if [ -f "$KEYCHAIN_PASS_FILE" ]; then
  security unlock-keychain -p "$(cat "$KEYCHAIN_PASS_FILE")" "$KEYCHAIN" 2>/dev/null || true
fi
security find-identity -v -p codesigning | grep -q "Apple Distribution" \
  || { echo "error: no Apple Distribution identity; run scripts/ios-signing-setup.sh" >&2; exit 1; }

echo "==> xcodegen"
(cd "$IOS" && xcodegen generate >/dev/null)

mkdir -p "$WORK"
ARCHIVE="$WORK/Control-V-$version-$build.xcarchive"
rm -rf "$ARCHIVE" "$WORK/export"

echo "==> archive $version ($build)"
nice -n 10 xcodebuild archive \
  -project "$IOS/ControlV.xcodeproj" \
  -scheme Control-V \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  -derivedDataPath "$WORK/dd" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$KEY_PATH" \
  -authenticationKeyID "$KEY_ID" \
  -authenticationKeyIssuerID "$ISSUER" \
  | tail -5

echo "==> export + upload"
nice -n 10 xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$IOS/ExportOptions.plist" \
  -exportPath "$WORK/export" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$KEY_PATH" \
  -authenticationKeyID "$KEY_ID" \
  -authenticationKeyIssuerID "$ISSUER" \
  | tail -5

echo "==> uploaded $version ($build); TestFlight processing takes a few minutes"
