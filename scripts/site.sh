BUCKET=$1
PROFILE=$2
DISTRIBUTION_ID=$3
ENV=$4

aws s3 sync site "s3://$BUCKET/site" --delete --profile "$PROFILE" --exclude ".well-known/*"

aws s3 cp "site/.well-known/$ENV/apple-app-site-association" \
  "s3://$BUCKET/site/.well-known/apple-app-site-association" \
  --content-type application/json --profile "$PROFILE"

aws cloudfront create-invalidation --distribution-id "$DISTRIBUTION_ID" \
  --paths "/*" \
  --profile "$PROFILE" \
  >/dev/null