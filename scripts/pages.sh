#!/usr/bin/env bash
# Builds pages/ (the blog, rendered by Jaspr) and stages it with site/ into
# <out-dir>, which scripts/site.sh syncs. Run on its own to preview:
#
#   scripts/pages.sh build/site && python3 -m http.server -d build/site
#
# Only the blog's own files are copied: `jaspr build` also writes an
# index.html for `/` and the packages it ran with, neither of which belongs
# on the site. Every page it adds goes into the staged sitemap.xml.
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "usage: $0 <out-dir>" >&2
  exit 2
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT=$1
BUILT="$ROOT/pages/build/jaspr"

(cd "$ROOT/pages" && dart pub get >/dev/null && dart run jaspr_cli:jaspr build)

mkdir -p "$OUT"
rsync -a --delete "$ROOT/site/" "$OUT/"
rsync -a --exclude '.gitkeep' "$BUILT/blog.html" "$BUILT/blog.xml" "$BUILT/blog" "$OUT/"

{
  grep -v '</urlset>' "$ROOT/site/sitemap.xml"
  (cd "$BUILT" && find blog.html blog -name '*.html' | sort | sed 's#^#    <url><loc>https://heart-of.me/#; s#$#</loc></url>#')
  echo '</urlset>'
} > "$OUT/sitemap.xml"
