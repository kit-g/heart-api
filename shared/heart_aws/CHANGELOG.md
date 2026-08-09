# Changelog

## 1.0.1

- Fix: SigV4 credential scope is computed per request — a signer instance older
  than ~15 minutes froze its X-Amz-Date and AWS began rejecting its signatures.
- Fix: request bodies are UTF-8 encoded before hashing (previously UTF-16 code
  units, corrupting signatures for non-ASCII payloads).
- Fix: S3 tagging XML parsing handles empty tag values.

## 1.0.0

- Initial version.
