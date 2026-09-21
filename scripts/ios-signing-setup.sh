#!/bin/bash
# Recreate the iOS distribution signing setup on a Mac, without Xcode's UI.
#
#   bash scripts/ios-signing-setup.sh            # profiles only (safe to re-run)
#   bash scripts/ios-signing-setup.sh --cert     # also mint a new Apple Distribution cert
#
# Why this exists: the team's App Store Connect API key is an App Manager key,
# and Apple refuses cloud signing for it, so `xcodebuild -allowProvisioningUpdates`
# cannot create App Store profiles. We create them through the API instead and
# keep the distribution identity in its own keychain (no login-keychain prompts
# during an unattended upload).
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
API="node $REPO/scripts/asc-api.js"
TEAM="5ZFYF422LX"
KEYCHAIN_NAME="controlv-signing.keychain"
KEYCHAIN="$HOME/Library/Keychains/$KEYCHAIN_NAME-db"
PASS_FILE="$HOME/.config/ctrlv/signing-keychain-password"
PROFILE_DIR="$HOME/Library/MobileDevice/Provisioning Profiles"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Apple's bundle-id records; the profile names are what ExportOptions.plist pins.
BUNDLES=("MP9DUGGFQT:app:info.controlv.ios" "BZ9FU6X789:share:info.controlv.ios.share"
         "LMCLH98YCY:keyboard:info.controlv.ios.keyboard" "67H6B42C5L:translation:info.controlv.ios.translation")

mint_certificate() {
  echo "==> new Apple Distribution certificate"
  openssl req -new -newkey rsa:2048 -nodes -keyout "$WORK/dist.key" -out "$WORK/dist.csr" \
    -subj "/emailAddress=info@control-v.info/CN=Viko Holdings LLC/C=US" 2>/dev/null
  node -e 'const fs=require("fs");fs.writeFileSync(process.argv[2],JSON.stringify({data:{type:"certificates",
    attributes:{certificateType:"DISTRIBUTION",csrContent:fs.readFileSync(process.argv[1],"utf8")}}}))' \
    "$WORK/dist.csr" "$WORK/cert-body.json"
  $API POST /v1/certificates "$WORK/cert-body.json" > "$WORK/cert.json"
  node -e 'const fs=require("fs");const r=fs.readFileSync(process.argv[1],"utf8");
    const a=JSON.parse(r.slice(r.indexOf("{"))).data.attributes;
    fs.writeFileSync(process.argv[2],Buffer.from(a.certificateContent,"base64"));console.log(a.name)' \
    "$WORK/cert.json" "$WORK/dist.cer"
  openssl x509 -inform DER -in "$WORK/dist.cer" -out "$WORK/dist.pem"

  local p12pass keychainpass
  p12pass=$(openssl rand -hex 16)
  openssl pkcs12 -export -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1 \
    -inkey "$WORK/dist.key" -in "$WORK/dist.pem" -name "Apple Distribution: Viko Holdings LLC" \
    -out "$WORK/dist.p12" -passout "pass:$p12pass"

  mkdir -p "$(dirname "$PASS_FILE")"
  if [ ! -f "$PASS_FILE" ]; then
    openssl rand -hex 16 | tr -d '\n' > "$PASS_FILE"; chmod 600 "$PASS_FILE"
  fi
  keychainpass=$(cat "$PASS_FILE")
  security delete-keychain "$KEYCHAIN_NAME" 2>/dev/null || true
  security create-keychain -p "$keychainpass" "$KEYCHAIN_NAME"
  security set-keychain-settings -lut 36000 "$KEYCHAIN_NAME"
  security unlock-keychain -p "$keychainpass" "$KEYCHAIN_NAME"
  security import "$WORK/dist.p12" -k "$KEYCHAIN" -P "$p12pass" \
    -T /usr/bin/codesign -T /usr/bin/xcodebuild -T /usr/bin/security -T /usr/bin/productbuild
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychainpass" "$KEYCHAIN_NAME" >/dev/null
  # Keep every keychain already in the search list: dropping one would hide the
  # user's own certificates (login, openvpn, ...).
  local -a search
  while IFS= read -r line; do
    line="${line//\"/}"; line="${line// /}"
    [ -n "$line" ] && [ "$line" != "$KEYCHAIN" ] && search+=("$line")
  done < <(security list-keychains -d user)
  security list-keychains -d user -s "${search[@]}" "$KEYCHAIN"
}

refresh_profiles() {
  local cert_id
  cert_id=$($API GET "/v1/certificates?limit=50&fields[certificates]=certificateType,name" \
    | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const j=JSON.parse(s.slice(s.indexOf("{")));
      const c=j.data.filter(x=>x.attributes.certificateType==="DISTRIBUTION").pop();
      if(!c){console.error("no Apple Distribution certificate; rerun with --cert");process.exit(1)}console.log(c.id)})')
  echo "==> certificate $cert_id"
  mkdir -p "$PROFILE_DIR"
  for entry in "${BUNDLES[@]}"; do
    local bundle_id="${entry%%:*}" rest="${entry#*:}" tag name
    tag="${rest%%:*}"; name="ControlV AppStore $tag"
    # A profile is immutable once issued: delete the old one, then reissue it
    # against the current certificate.
    $API GET "/v1/profiles?limit=200&fields[profiles]=name" \
      | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const j=JSON.parse(s.slice(s.indexOf("{")));
        const p=j.data.find(x=>x.attributes.name===process.argv[1]);if(p)console.log(p.id)})' "$name" \
      | while read -r old; do [ -n "$old" ] && $API DELETE "/v1/profiles/$old" >/dev/null; done
    node -e 'const fs=require("fs");const [bid,name,cert,out]=process.argv.slice(1);
      fs.writeFileSync(out,JSON.stringify({data:{type:"profiles",attributes:{name,profileType:"IOS_APP_STORE"},
      relationships:{bundleId:{data:{type:"bundleIds",id:bid}},certificates:{data:[{type:"certificates",id:cert}]}}}}))' \
      "$bundle_id" "$name" "$cert_id" "$WORK/profile.json"
    $API POST /v1/profiles "$WORK/profile.json" > "$WORK/profile-out.json"
    PROFILE_DIR="$PROFILE_DIR" node -e 'const fs=require("fs");const r=fs.readFileSync(process.argv[1],"utf8");
      const a=JSON.parse(r.slice(r.indexOf("{"))).data.attributes;
      fs.writeFileSync(`${process.env.PROFILE_DIR}/${a.uuid}.mobileprovision`,Buffer.from(a.profileContent,"base64"));
      console.log("   ", a.name, a.uuid)' "$WORK/profile-out.json"
  done
}

for arg in "$@"; do [ "$arg" = "--cert" ] && mint_certificate; done
refresh_profiles
security find-identity -v -p codesigning | grep "Apple Distribution" || true
echo "==> ready: bash scripts/ios-upload.sh --bump"
