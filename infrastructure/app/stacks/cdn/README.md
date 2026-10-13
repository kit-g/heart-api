# Public media and private transfers

The content bucket serves public exercise assets, catalogs, workout images
and avatars through the media distribution. Runtime `imports/`, `exports/`,
`uploads/` and `exercise-uploads/` are private.

Two controls enforce that boundary:

- The S3 bucket policy explicitly denies CloudFront reads of those prefixes.
  API-role access and presigned S3 downloads still work.
- Every media cache behavior runs `functions/private_media.js` on
  viewer-request, before cache lookup. This also blocks objects cached before
  the policy changed; changing an origin policy alone would leave them readable
  until cache expiry.

Roll out the distribution/function and bucket-policy changes together, wait
for CloudFront deployment, and verify an existing private key returns 403
while an existing public asset returns 200. An export's presigned S3 link
should still download until its expiry. Purge historical cached private paths
with a distribution invalidation after deployment:

```sh
aws cloudfront create-invalidation --distribution-id <media-distribution-id> \
  --paths '/imports/*' '/exports/*' '/uploads/*' '/exercise-uploads/*'
```

The dated Hevy reference corpus documented elsewhere lives in the static
bucket. Appending that corpus path to the media hostname does not test this
boundary: a missing S3 object can itself return 403.
