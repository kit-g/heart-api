#!/usr/bin/env bash
# Renders scripts/og/card.html to site/assets/og.png (1200×630), the image link
# previews use. Needs Google Chrome; run from anywhere.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"

"$CHROME" --headless=new --disable-gpu --hide-scrollbars \
  --window-size=1200,630 --force-device-scale-factor=1 \
  --virtual-time-budget=5000 \
  --screenshot="$ROOT/site/assets/og.png" \
  "file://$ROOT/scripts/og/card.html" 2>/dev/null

echo "wrote site/assets/og.png — bump ?v= in the og:image tags so caches refetch it"
