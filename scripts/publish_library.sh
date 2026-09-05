#!/usr/bin/env bash
# Publishes the exercise library to the CDN as static, unauthenticated JSON
# and invalidates it: builds api/bin/publish_library.dart's output (one file
# per locale plus the manifest, exactly the GET /v1/exercises body for that
# locale), uploads it to S3 under the cache/content-type headers the app
# relies on, then invalidates the media distribution for those paths so a
# publish lands within minutes rather than the cache policy's 24h default.
#
# Usage: scripts/publish_library.sh <bucket> <distribution-id>
#
# Run from the repo root, after content/exercise_library.yml has been synced
# to Postgres (scripts/library_locales.py) — this only ever reads the
# database, it never writes it.
#
# Connection: PG_HOST/PG_PORT/PG_DATABASE/PG_USER/PG_PASSWORD must already be
# set — the same variable names the API Lambda gets; the generator reads them
# via PostgresConfig.fromEnv, not the full AppConfig, so nothing else needs
# to be set.
set -euo pipefail

if [ $# -ne 2 ]; then
  echo "usage: $0 <bucket> <distribution-id>" >&2
  exit 2
fi

BUCKET=$1
DISTRIBUTION_ID=$2

# Real CloudFront distribution ids are upper-case alphanumeric (e.g.
# E28G19V18R0DYG) — this also catches an unreplaced `terraform`/workflow
# placeholder before any S3 upload happens, rather than failing on the very
# last line after the CDN objects are already live.
if [[ ! "$DISTRIBUTION_ID" =~ ^[A-Z0-9]{10,20}$ ]]; then
  echo "error: '$DISTRIBUTION_ID' doesn't look like a CloudFront distribution id — refusing to publish" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."
API_DIR="$REPO_ROOT/api"
OUT_DIR="$(mktemp -d)"
trap 'rm -rf "$OUT_DIR"' EXIT

# Single source for the locale set: content/exercise_library.yml's own
# `locales:` list (via library_locales.py's own path resolution), so adding a
# locale there is enough — nothing here or in the app needs to change to
# publish it.
LOCALES="$(
  uv run --project "$REPO_ROOT" python -c "
import sys, os, yaml
sys.path.insert(0, '$SCRIPT_DIR')
from library_locales import content_dir
with open(os.path.join(content_dir(), 'exercise_library.yml')) as f:
    print(','.join(yaml.safe_load(f)['locales']))
"
)"

echo ">> Generating exercise library CDN objects for: $LOCALES"
(cd "$API_DIR" && dart pub get && dart run bin/publish_library.dart "$OUT_DIR" "$LOCALES")

echo ">> Uploading to s3://$BUCKET/static/exercises/"
aws s3 cp "$OUT_DIR/index.json" "s3://$BUCKET/static/exercises/index.json" \
  --content-type application/json \
  --cache-control "public, max-age=300"

for f in "$OUT_DIR"/*.json; do
  name="$(basename "$f")"
  [ "$name" = "index.json" ] && continue
  aws s3 cp "$f" "s3://$BUCKET/static/exercises/$name" \
    --content-type application/json \
    --cache-control "public, max-age=3600"
done

echo ">> Invalidating /static/exercises/* on $DISTRIBUTION_ID"
aws cloudfront create-invalidation \
  --distribution-id "$DISTRIBUTION_ID" \
  --paths "/static/exercises/*" \
  >/dev/null
