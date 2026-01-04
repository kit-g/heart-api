BUCKET=$1
PROFILE=$2
DISTRIBUTION_ID=$3

aws s3 sync infrastructure/media/site "s3://$BUCKET/site" --delete --profile "$PROFILE"

aws cloudfront create-invalidation --distribution-id "$DISTRIBUTION_ID" \
  --paths "/*" \
  --profile "$PROFILE" \
  >/dev/null