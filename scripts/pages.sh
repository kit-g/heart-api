#!/usr/bin/env bash
# Builds pages/ (the blog, rendered by Jaspr) for one environment and stages
# it with site/ into <out-dir>, which scripts/site.sh syncs. Each environment
# gets its own posts (pages/posts/<env>/) and its own origin in links, feeds
# and previews. Run on its own to preview:
#
#   scripts/pages.sh dev build/site && python3 -m http.server -d build/site
#
# Only the blog's own files are copied: `jaspr build` also writes an
# index.html for `/` and the packages it ran with, neither of which belongs
# on the site. Every page it adds goes into the staged sitemap.xml.
set -euo pipefail

if [ $# -ne 2 ] || { [ "$1" != dev ] && [ "$1" != prod ]; }; then
  echo "usage: $0 <dev|prod> <out-dir>" >&2
  exit 2
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV=$1
OUT=$2
BUILT="$ROOT/pages/build/jaspr"
# Matches `origin` in pages/lib/posts.dart.
if [ "$ENV" = prod ]; then ORIGIN=https://heart-of.me; else ORIGIN=https://dev.heart-of.me; fi

(cd "$ROOT/pages" && dart pub get >/dev/null && dart run jaspr_cli:jaspr build --dart-define=HEART_ENV="$ENV")

mkdir -p "$OUT"
rsync -a --delete "$ROOT/site/" "$OUT/"
rsync -a --exclude '.gitkeep' "$BUILT/blog.html" "$BUILT/blog.xml" "$BUILT/blog" "$OUT/"

{
  grep -v '</urlset>' "$ROOT/site/sitemap.xml"
  (cd "$BUILT" && find blog.html blog -name '*.html' | sort | sed "s#^#    <url><loc>$ORIGIN/#; s#\$#</loc></url>#")
  echo '</urlset>'
} > "$OUT/sitemap.xml"
