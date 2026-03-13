#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${OPENROUTER_API_KEY:-}" ]]; then
  echo "OPENROUTER_API_KEY is required" >&2
  exit 1
fi

ITERATIONS="${1:-3}"
TEXT="${2:-Hola mi nombre es juan davod y soy el creador de control.v una herramient apara hacer más eficiente la traduccion en ambientes lborales de equipos con multiple idiomas}"
PROMPT="${3:-Translate to English. Return only the final translated text.}"

MODELS=(
  "moonshotai/kimi-k2.5"
  "x-ai/grok-4-fast"
  "x-ai/grok-4.1-fast"
  "google/gemini-2.5-flash-lite"
)

TMP_DIR="$(mktemp -d /tmp/ctrlv-openrouter-models.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
  exit 1
fi

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

summarize_metric() {
  local file="$1"
  local avg
  avg=$(awk '{sum += $1} END {if (NR > 0) printf "%.3f", sum / NR; else print "0.000"}' "$file")
  echo "avg=${avg}s p50=$(percentile "$file" 50)s p95=$(percentile "$file" 95)s min=$(sort -n "$file" | head -n1)s max=$(sort -n "$file" | tail -n1)s"
}

estimate_max_tokens() {
  local text="$1"
  local length=${#text}
  local estimated=$(((length + 2) / 3))
  if (( estimated < 96 )); then
    estimated=96
  elif (( estimated > 4096 )); then
    estimated=4096
  fi
  echo "$estimated"
}

MAX_TOKENS="$(estimate_max_tokens "$TEXT")"

echo "iterations=$ITERATIONS"
echo "text_length=${#TEXT}"
echo "max_tokens=$MAX_TOKENS"
echo

for MODEL in "${MODELS[@]}"; do
  TOTAL_FILE="$TMP_DIR/$(echo "$MODEL" | tr '/:.' '_').total"
  TTFB_FILE="$TMP_DIR/$(echo "$MODEL" | tr '/:.' '_').ttfb"
  COST_FILE="$TMP_DIR/$(echo "$MODEL" | tr '/:.' '_').cost"

  echo "MODEL $MODEL"
  for i in $(seq 1 "$ITERATIONS"); do
    PAYLOAD=$(jq -n \
      --arg model "$MODEL" \
      --arg prompt "$PROMPT" \
      --arg text "$TEXT" \
      --argjson max_tokens "$MAX_TOKENS" \
      '{
        model:$model,
        temperature:0.1,
        max_tokens:$max_tokens,
        reasoning:{effort:"none", exclude:true},
        messages:[
          {role:"system", content:$prompt},
          {role:"user", content:$text}
        ]
      }')

    RESPONSE_FILE="$TMP_DIR/response.json"
    METRICS=$(curl -sS https://openrouter.ai/api/v1/chat/completions \
      -H "Authorization: Bearer $OPENROUTER_API_KEY" \
      -H "Content-Type: application/json" \
      -H "HTTP-Referer: https://control-v.info" \
      -H "X-Title: ctrl+v" \
      -d "$PAYLOAD" \
      -o "$RESPONSE_FILE" \
      -w "%{time_total} %{time_starttransfer} %{http_code}")

    TOTAL=$(echo "$METRICS" | awk '{print $1}')
    TTFB=$(echo "$METRICS" | awk '{print $2}')
    STATUS=$(echo "$METRICS" | awk '{print $3}')
    MODEL_USED=$(jq -r '.model // empty' "$RESPONSE_FILE")
    PROVIDER_USED=$(jq -r '.provider // empty' "$RESPONSE_FILE")
    COST=$(jq -r '.usage.cost // 0' "$RESPONSE_FILE")
    CONTENT=$(jq -r '.choices[0].message.content // empty' "$RESPONSE_FILE")
    FINISH=$(jq -r '.choices[0].finish_reason // empty' "$RESPONSE_FILE")

    echo "$TOTAL" >> "$TOTAL_FILE"
    echo "$TTFB" >> "$TTFB_FILE"
    echo "$COST" >> "$COST_FILE"

    printf "  #%02d status=%s total=%ss ttfb=%ss finish=%s provider=%s model=%s cost=%s content=%s\n" \
      "$i" "$STATUS" "$TOTAL" "$TTFB" "$FINISH" "${PROVIDER_USED:-n/a}" "${MODEL_USED:-n/a}" "$COST" "$CONTENT"
  done

  echo "  total: $(summarize_metric "$TOTAL_FILE")"
  echo "  ttfb:  $(summarize_metric "$TTFB_FILE")"
  echo
done
