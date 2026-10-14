# Public media and private transfers

The content bucket serves public exercise assets, catalogs, workout images
and avatars through the media distribution. Runtime `imports/`, `exports/`,
`uploads/` and `exercise-uploads/` are private.

The S3 bucket policy explicitly denies CloudFront reads of those prefixes.
API-role access and presigned S3 downloads still work.

The rollout requires a one-time cache invalidation **after** the bucket deny
is active. An origin policy is not consulted on a cache hit, so existing
cached objects remain readable until invalidation completes or they expire.
Invalidate the whole media cache to cover encoded URL variants as well as
the ordinary private paths:

```sh
invalidation_id=$(aws cloudfront create-invalidation \
  --distribution-id <media-distribution-id> --paths '/*' \
  --query 'Invalidation.Id' --output text)
aws cloudfront wait invalidation-completed \
  --distribution-id <media-distribution-id> --id "$invalidation_id"
```

The full invalidation also clears public assets, which CloudFront can fetch
again normally. Do not mark rollout complete until the invalidation has
finished and an existing private key returns 403 while an existing public
asset returns 200. An export's unexpired presigned S3 link should still download.

The dated Hevy reference corpus documented elsewhere lives in the static
bucket. Appending that corpus path to the media hostname does not test this
boundary: a missing S3 object can itself return 403.
