#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCENARIO="${1:-trial}"
APPEARANCE="${2:-light}"
OUT_DIR="${PROJECT_DIR}/artifacts/menu-previews"
OUT_FILE="${OUT_DIR}/menu-${SCENARIO}-${APPEARANCE}.png"

cd "${PROJECT_DIR}"

echo "==> Building debug binary..."
swift build -c debug

mkdir -p "${OUT_DIR}"
rm -f "${OUT_FILE}"

echo "==> Rendering menu snapshot (${SCENARIO}, ${APPEARANCE})..."
".build/debug/InstantTranslator" \
    --render-menu-snapshot "${OUT_FILE}" \
    --menu-scenario "${SCENARIO}" \
    --menu-appearance "${APPEARANCE}"

if [[ ! -f "${OUT_FILE}" ]]; then
    echo "Snapshot was not created: ${OUT_FILE}" >&2
    exit 1
fi

echo "==> Snapshot ready:"
echo "${OUT_FILE}"
