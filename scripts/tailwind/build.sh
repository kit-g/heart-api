#!/usr/bin/env bash
# Compiles the site's Tailwind classes into site/assets/tailwind.css, which the
# pages link. Run before previewing site/ locally; scripts/site.sh runs it on
# every deploy. Uses Tailwind's standalone CLI (first-party plugins built in),
# downloaded once into build/.
set -euo pipefail

VERSION=v3.4.19
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

case "$(uname -s)-$(uname -m)" in
  Darwin-arm64) PLATFORM=macos-arm64 ;;
  Darwin-x86_64) PLATFORM=macos-x64 ;;
  Linux-x86_64) PLATFORM=linux-x64 ;;
  Linux-aarch64) PLATFORM=linux-arm64 ;;
  *) echo "no Tailwind binary for $(uname -sm)" >&2; exit 1 ;;
esac

CLI="$ROOT/build/tailwindcss-$VERSION-$PLATFORM"
if [ ! -x "$CLI" ]; then
  mkdir -p "$ROOT/build"
  curl -fsSL -o "$CLI" \
    "https://github.com/tailwindlabs/tailwindcss/releases/download/$VERSION/tailwindcss-$PLATFORM"
  chmod +x "$CLI"
fi

cd "$ROOT"
"$CLI" --config scripts/tailwind/tailwind.config.js \
  --input scripts/tailwind/input.css \
  --output site/assets/tailwind.css \
  --minify
