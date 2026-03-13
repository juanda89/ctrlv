#!/usr/bin/env bash
set -euo pipefail

ENDPOINT="${1:-https://hdfhonbgkkiffhkwoivd.functions.supabase.co/translate}"
ITERATIONS="${2:-10}"
TEXT="${3:-hola amiguita}"
PROMPT="${4:-Translate to English. Return only the final translated text.}"
INSTALL_PREFIX="benchmark-$(date +%s)"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
  exit 1
fi

TMP_DIR="$(mktemp -d /tmp/ctrlv-benchmark.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

TOTAL_FILE="$TMP_DIR/total.txt"
TTFB_FILE="$TMP_DIR/ttfb.txt"

summarize_metric() {
  local file="$1"
  local count
  count=$(wc -l < "$file" | tr -d ' ')
  local avg
  avg=$(awk '{sum += $1} END {if (NR > 0) printf "%.3f", sum / NR; else print "0.000"}' "$file")
  local min
  min=$(sort -n "$file" | head -n 1)
  local max
  max=$(sort -n "$file" | tail -n 1)
  local p50
  p50=$(percentile "$file" 50)
  local p95
  p95=$(percentile "$file" 95)

  echo "  count=$count"
  echo "  avg=${avg}s"
  echo "  min=${min}s"
  echo "  p50=${p50}s"
  echo "  p95=${p95}s"
  echo "  max=${max}s"
}

percentile() {
  local file="$1"
  local pct="$2"
  sort -n "$file" | awk -v pct="$pct" '
    { values[NR] = $1 }
    END {
      if (NR == 0) {
        print "0.000"
        exit
      }
      rank = int((pct / 100) * NR + 0.999999)
      if (rank < 1) rank = 1
      if (rank > NR) rank = NR
      printf "%.3f", values[rank]
    }
  '
}

echo "endpoint=$ENDPOINT"
echo "iterations=$ITERATIONS"
echo "text_length=${#TEXT}"
echo

for i in $(seq 1 "$ITERATIONS"); do
  INSTALL_ID="$INSTALL_PREFIX-$i"
  PAYLOAD=$(jq -n \
    --arg text "$TEXT" \
    --arg systemPrompt "$PROMPT" \
    --arg installID "$INSTALL_ID" \
    '{text:$text, systemPrompt:$systemPrompt, installID:$installID}')

  RESPONSE_FILE="$TMP_DIR/response-$i.json"
  METRICS=$(curl -sS \
    -o "$RESPONSE_FILE" \
    -w "%{time_total} %{time_starttransfer} %{http_code}" \
    -X POST "$ENDPOINT" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD")

  TOTAL=$(echo "$METRICS" | awk '{print $1}')
  TTFB=$(echo "$METRICS" | awk '{print $2}')
  STATUS=$(echo "$METRICS" | awk '{print $3}')
  BODY=$(cat "$RESPONSE_FILE")

  echo "$TOTAL" >> "$TOTAL_FILE"
  echo "$TTFB" >> "$TTFB_FILE"

  printf "#%02d status=%s total=%ss ttfb=%ss body=%s\n" "$i" "$STATUS" "$TOTAL" "$TTFB" "$BODY"
done

echo
echo "total_latency:"
summarize_metric "$TOTAL_FILE"
echo
echo "time_to_first_byte:"
summarize_metric "$TTFB_FILE"
