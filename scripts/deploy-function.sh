#!/usr/bin/env bash
# Deploy one Edge Function through the Management API with verify_jwt=false
# (the functions validate the app's own session token; a JWT gate would
# break every client). Uploads the entrypoint plus every local module it
# imports, with repo-relative paths, which is how the CLI registered the
# existing versions.
#
# Usage: SUPABASE_ACCESS_TOKEN=sbp_... scripts/deploy-function.sh translate [project-ref]
set -euo pipefail

SLUG="${1:?function slug required}"
REF="${2:-hdfhonbgkkiffhkwoivd}"
: "${SUPABASE_ACCESS_TOKEN:?SUPABASE_ACCESS_TOKEN is required}"
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }
command -v deno >/dev/null || { echo "deno is required" >&2; exit 1; }

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
ENTRY="supabase/functions/$SLUG/index.ts"
[[ -f "$ENTRY" ]] || { echo "No such function: $ENTRY" >&2; exit 1; }

ARGS=(-F "metadata={\"entrypoint_path\":\"$ENTRY\",\"name\":\"$SLUG\",\"verify_jwt\":false}")
while IFS= read -r module; do
  ARGS+=(-F "file=@$module;filename=$module")
  echo "  + $module"
done < <(deno info --json --config supabase/functions/deno.json "$ENTRY" \
  | jq -r '.modules[].specifier' | grep '^file://' | sed "s#file://$ROOT/##" | sort)

RESULT="$(curl -sS -m 300 -X POST "https://api.supabase.com/v1/projects/$REF/functions/deploy?slug=$SLUG" \
  -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" "${ARGS[@]}")"
echo "$RESULT" | jq -r '"deployed \(.slug) v\(.version) status=\(.status) verify_jwt=\(.verify_jwt)"' \
  || { echo "Deploy failed: $RESULT" >&2; exit 1; }
