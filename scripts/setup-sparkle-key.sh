#!/bin/bash
set -euo pipefail

# Creates/reads Sparkle EdDSA key from Keychain and writes SUPublicEDKey in Info.plist.

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INFO_PLIST="${PROJECT_DIR}/Resources/Info.plist"
GENERATE_KEYS_BIN="${PROJECT_DIR}/.build/artifacts/sparkle/Sparkle/bin/generate_keys"

if [[ ! -x "${GENERATE_KEYS_BIN}" ]]; then
  echo "Missing ${GENERATE_KEYS_BIN}. Run: swift package resolve"
  exit 1
fi

echo "==> Reading Sparkle public key from Keychain"
KEY_OUTPUT="$("${GENERATE_KEYS_BIN}" -p 2>/dev/null || true)"

if [[ -z "${KEY_OUTPUT}" ]]; then
  echo "==> No existing key found; generating a new one"
  KEY_OUTPUT="$("${GENERATE_KEYS_BIN}" 2>/dev/null || true)"
fi

PUBLIC_KEY="$(printf '%s\n' "${KEY_OUTPUT}" | rg -o '[A-Za-z0-9+/]{40,}={0,2}' -m1 || true)"
if [[ -z "${PUBLIC_KEY}" ]]; then
  echo "Could not extract Sparkle public key."
  exit 1
fi

echo "==> Updating SUPublicEDKey in ${INFO_PLIST}"
/usr/libexec/PlistBuddy -c "Set :SUPublicEDKey ${PUBLIC_KEY}" "${INFO_PLIST}" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string ${PUBLIC_KEY}" "${INFO_PLIST}"

echo "SUPublicEDKey updated:"
echo "${PUBLIC_KEY}"
