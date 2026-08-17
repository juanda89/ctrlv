#!/bin/bash
set -euo pipefail

# Rebuilds docs/assets/tailwind.css from docs/*.html.
#
# Run this whenever a docs page adds or removes Tailwind utility classes —
# the stylesheet is compiled ahead of time (no runtime CDN) so new classes
# won't style themselves until this script runs.
#
# Usage: bash scripts/build-docs-css.sh

DIR="$(cd "$(dirname "$0")/docs-css" && pwd)"
cd "${DIR}"

if [ ! -d node_modules ]; then
    echo "==> Installing pinned Tailwind toolchain..."
    npm install --no-audit --no-fund
fi

echo "==> Compiling docs/assets/tailwind.css..."
npx tailwindcss -c tailwind.config.js -i input.css -o ../../docs/assets/tailwind.css --minify

echo "==> Done: $(ls -la ../../docs/assets/tailwind.css | awk '{print $5 " bytes"}')"
