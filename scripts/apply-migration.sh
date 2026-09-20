#!/usr/bin/env bash
# Apply one SQL migration file to the hosted project through the Management
# API and record it in supabase_migrations.schema_migrations.
#
# Why not the CLI: both Supabase CLIs installed on the dev Mac are Bun
# "legacy" builds that hang or fork-loop on remote commands (see CLAUDE.md).
#
# Usage: SUPABASE_ACCESS_TOKEN=sbp_... scripts/apply-migration.sh supabase/migrations/<file>.sql [project-ref]
set -euo pipefail

FILE="${1:?migration file required}"
REF="${2:-hdfhonbgkkiffhkwoivd}"
: "${SUPABASE_ACCESS_TOKEN:?SUPABASE_ACCESS_TOKEN is required}"
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }

query() {
  jq -n --arg q "$1" '{query:$q}' | curl -sS -m 180 -X POST \
    "https://api.supabase.com/v1/projects/$REF/database/query" \
    -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
    -H "Content-Type: application/json" --data-binary @-
}

BASENAME="$(basename "$FILE" .sql)"
VERSION="${BASENAME%%_*}"
NAME="${BASENAME#*_}"

echo "Applying $BASENAME to $REF"
RESULT="$(query "$(cat "$FILE")")"
if echo "$RESULT" | jq -e 'type=="object" and has("message")' >/dev/null 2>&1; then
  echo "Failed: $RESULT" >&2
  exit 1
fi

query "insert into supabase_migrations.schema_migrations (version, name, statements)
       values ('$VERSION', '$NAME', array['applied via scripts/apply-migration.sh'])
       on conflict (version) do nothing" >/dev/null
echo "Recorded $VERSION $NAME"
