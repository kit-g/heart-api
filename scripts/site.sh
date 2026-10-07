#!/usr/bin/env bash
# Syncs site/ to S3 and invalidates the CloudFront distribution.
#
# Usage: scripts/site.sh <bucket> <aws-profile> <distribution-id> <env>
#   env picks which .well-known/<env>/ association files and robots/<env>.txt ship.
set -euo pipefail

if [ $# -ne 4 ]; then
  echo "usage: $0 <bucket> <aws-profile> <distribution-id> <env>" >&2
  exit 2
fi

BUCKET=$1
PROFILE=$2
DISTRIBUTION_ID=$3
ENV=$4

"$(dirname "$0")/tailwind/build.sh"

# data/ belongs to heart-of-yours: its release workflow uploads the JSON the
# feature and changelog pages render. Excluded, --delete would wipe it.
aws s3 sync site "s3://$BUCKET/site" --delete --profile "$PROFILE" \
  --exclude ".well-known/*" --exclude "connect/*" --exclude "robots/*" --exclude "robots.txt" --exclude "data/*"

aws s3 cp "site/.well-known/$ENV/apple-app-site-association" \
  "s3://$BUCKET/site/.well-known/apple-app-site-association" \
  --content-type application/json --profile "$PROFILE"

aws s3 cp "site/.well-known/$ENV/assetlinks.json" \
  "s3://$BUCKET/site/.well-known/assetlinks.json" \
  --content-type application/json --profile "$PROFILE"

# dev mirrors prod's pages, so it shuts crawlers out; only prod is indexed.
aws s3 cp "site/.well-known/$ENV/oauth-authorization-server" \
  "s3://$BUCKET/site/.well-known/oauth-authorization-server" \
  --content-type application/json --profile "$PROFILE"
aws s3 cp "site/connect/$ENV.js" "s3://$BUCKET/site/assets/connect-config.js" \
  --content-type text/javascript --profile "$PROFILE"
aws s3 cp "site/robots/$ENV.txt" "s3://$BUCKET/site/robots.txt" \
  --content-type text/plain --profile "$PROFILE"

aws cloudfront create-invalidation --distribution-id "$DISTRIBUTION_ID" \
  --paths "/*" \
  --profile "$PROFILE" \
  >/dev/null
