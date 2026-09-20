#!/usr/bin/env bash
# Per-request phase timings, upstream provider and cost from the live
# /translate endpoint (X-Ctrlv-Debug: 1). Use it to A/B provider routing
# (OPENROUTER_PROVIDER_SORT secret) or model changes.
#
# Usage: CTRLV_DEBUG_TOKEN=<secret> scripts/benchmark-translate-debug.sh [iterations=6] [label]
set -euo pipefail
ITER="${1:-6}"
LABEL="${2:-run}"
ENDPOINT="${ENDPOINT:-https://hdfhonbgkkiffhkwoivd.functions.supabase.co/translate}"
INSTALL_ID="${INSTALL_ID:-bench-$LABEL-$(date +%s)}"
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }

PROMPT="You are an expert bilingual writer. Re-express the text in English as a native speaker would. Return ONLY the final text, keep line breaks."
SHORT="hola, nos vemos mañana"
MEDIUM="Hola Marta, te adjunto la factura 2024-118 por 1,250 euros. Cualquier duda escríbeme a facturas@acme.com. Mañana paso por la oficina a las 10:30 para revisar los cambios del diseño y cerrar el presupuesto del trimestre. Gracias, Juan"
LONG="$MEDIUM $MEDIUM $MEDIUM $MEDIUM $MEDIUM $MEDIUM"

run_case() {
  local kind="$1" text="$2" i="$3"
  local out total json
  out="$(jq -n --arg t "$text" --arg p "$PROMPT" --arg id "$INSTALL_ID" '{text:$t,systemPrompt:$p,installID:$id}' \
    | curl -s -m 90 -X POST "$ENDPOINT" -H "Content-Type: application/json" -H "X-Ctrlv-Debug: ${CTRLV_DEBUG_TOKEN:-}" \
      --data-binary @- -w '\n%{time_total}')"
  total="$(tail -n1 <<<"$out")"
  json="$(sed '$d' <<<"$out")"
  jq -r --arg kind "$kind" --arg i "$i" --arg total "$total" '
    [$kind, $i, $total,
     ((.timings.modelMs // "-") | tostring) + "ms",
     ((.timings.rpcMs // "-") | tostring) + "ms",
     ((.timings.costUSD // "-") | tostring),
     (.timings.provider // .error // "-"),
     (if .retried == null then "-" else (.retried | tostring) end)] | @tsv' <<<"$json"
}

{
  printf 'text\tn\ttotal_s\tmodel\trpc\tcost_usd\tprovider\tretried\n'
  for kind in short medium long; do
    case $kind in short) text="$SHORT";; medium) text="$MEDIUM";; *) text="$LONG";; esac
    for ((i = 1; i <= ITER; i++)); do
      run_case "$kind" "$text" "$i"
    done
  done
} | column -t -s $'\t'
