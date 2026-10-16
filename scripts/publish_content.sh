#!/usr/bin/env bash
# Checks, renders and publishes the content the app reads from the CDN besides
# the exercise library: the program library (static/programs), "go easy on"
# (static/go-easy), the balance pairs (static/balance) and the example
# templates (static/templates). Each renderer checks its source first and
# refuses to render a file with a problem, so nothing broken is ever uploaded.
# The upload then invalidates those paths on the media distribution, so a
# publish lands within minutes.
#
# Usage:
#   scripts/publish_content.sh --check                       # check and render, upload nothing
#   scripts/publish_content.sh <bucket> <distribution-id>    # check, render, upload, invalidate
#
# Run from anywhere; it reads content/ and runs the scripts/ renderers.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."
OUT_DIR="$(mktemp -d)"
trap 'rm -rf "$OUT_DIR"' EXIT

case "${1:-}" in
  --check)
    UPLOAD=false
    ;;
  *)
    if [ $# -ne 2 ]; then
      echo "usage: $0 --check | <bucket> <distribution-id>" >&2
      exit 2
    fi
    UPLOAD=true
    BUCKET=$1
    DISTRIBUTION_ID=$2
    # A real distribution id is upper-case alphanumeric; this catches an
    # unreplaced placeholder before anything is uploaded.
    if [[ ! "$DISTRIBUTION_ID" =~ ^[A-Z0-9]{10,20}$ ]]; then
      echo "error: '$DISTRIBUTION_ID' doesn't look like a CloudFront distribution id — refusing to publish" >&2
      exit 2
    fi
    ;;
esac

render() {
  uv run --project "$REPO_ROOT" python "$SCRIPT_DIR/$1" --render "$OUT_DIR/$2"
}

echo ">> Checking and rendering"
render programs_content.py programs
render go_easy_content.py go-easy
render balance_content.py balance
# the example templates are written as served; this only proves they parse
uv run --project "$REPO_ROOT" python -c "import json, sys; json.load(open(sys.argv[1]))" \
  "$REPO_ROOT/content/sample_templates_en.json"
cp "$REPO_ROOT/content/sample_templates_en.json" "$OUT_DIR/templates"

if [ "$UPLOAD" = false ]; then
  echo ">> Checked: $(cd "$OUT_DIR" && ls | tr '\n' ' ')"
  exit 0
fi

for name in programs go-easy balance templates; do
  echo ">> Uploading s3://$BUCKET/static/$name"
  aws s3 cp "$OUT_DIR/$name" "s3://$BUCKET/static/$name" \
    --content-type application/json \
    --cache-control "public, max-age=300"
done

echo ">> Invalidating them on $DISTRIBUTION_ID"
aws cloudfront create-invalidation \
  --distribution-id "$DISTRIBUTION_ID" \
  --paths /static/programs /static/go-easy /static/balance /static/templates \
  >/dev/null
