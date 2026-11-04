part of '../db.dart';

// Personal access tokens (heart-api#111).
//
// The cap counts only active tokens, the same rule `ApiToken.isActive`
// applies; an empty result is unambiguously the cap.
const _createApiToken =
    '''
INSERT INTO api_tokens (user_id, name, purpose, token_hash, hint, expires_at)
SELECT @userId, @name, @purpose::text, @tokenHash::bytea, @hint, @expiresAt::timestamptz
WHERE (
  SELECT count(*)
  FROM api_tokens
  WHERE user_id = @userId
    AND grant_id IS NULL
    AND revoked_at IS NULL
    AND (expires_at IS NULL OR expires_at > now())
) < ${ApiToken.maxActive}
RETURNING id, name, purpose, hint, scopes, created_at, last_used_at, expires_at, revoked_at
''';

const _listApiTokens = '''
SELECT id, name, purpose, hint, scopes, created_at, last_used_at, expires_at, revoked_at
FROM api_tokens
WHERE user_id = @userId
  AND grant_id IS NULL
ORDER BY id DESC
''';

const _revokeApiToken = '''
UPDATE api_tokens
SET revoked_at = coalesce(revoked_at, now())
WHERE id = @tokenId::uuid
  AND user_id = @userId
  AND grant_id IS NULL
RETURNING id
''';

// Authenticates a token and counts the request in one round trip: the lookup
// bumps `last_used_at`, and the upsert advances both rate-limit windows by
// `@count` (0 for requests that don't count, such as an MCP handshake), each
// restarting once it has run out. Unknown, revoked and expired tokens return
// nothing and count nothing.
const _useApiToken = '''
WITH _token AS (
  UPDATE api_tokens
  SET last_used_at = now()
  WHERE token_hash = @tokenHash::bytea
    AND revoked_at IS NULL
    AND (expires_at IS NULL OR expires_at > now())
    -- an OAuth token works only on the resource it was issued for, and only
    -- while its grant stands: the grant's revocation is the authority, so a
    -- token minted concurrently with it is still refused
    AND (resource IS NULL OR resource = @resource)
    AND (grant_id IS NULL OR EXISTS (
      SELECT 1 FROM oauth_grants g WHERE g.id = api_tokens.grant_id AND g.revoked_at IS NULL
    ))
  RETURNING user_id, scopes, purpose, resource, grant_id
), _usage AS (
  INSERT INTO api_usage (user_id, minute_start, minute_count, day_start, day_count)
  SELECT user_id, now(), @count::int, now(), @count::int FROM _token
  ON CONFLICT (user_id) DO UPDATE
  SET minute_start = CASE WHEN api_usage.minute_start > now() - interval '1 minute'
                          THEN api_usage.minute_start ELSE now() END,
      minute_count = CASE WHEN api_usage.minute_start > now() - interval '1 minute'
                          THEN api_usage.minute_count + @count::int ELSE @count::int END,
      day_start    = CASE WHEN api_usage.day_start > now() - interval '1 day'
                          THEN api_usage.day_start ELSE now() END,
      day_count    = CASE WHEN api_usage.day_start > now() - interval '1 day'
                          THEN api_usage.day_count + @count::int ELSE @count::int END
  RETURNING user_id, minute_start, minute_count, day_start, day_count
)
SELECT t.user_id, t.scopes, t.purpose, t.resource, g.client_id,
       u.minute_start, u.minute_count, u.day_start, u.day_count
FROM _token t
JOIN _usage u USING (user_id)
LEFT JOIN oauth_grants g ON g.id = t.grant_id
''';

// Claims the day's export allowance. The outer SELECT reads the snapshot from
// before the UPDATE, so a refused claim reports the export it collided with.
const _claimApiExport = '''
WITH _claim AS (
  UPDATE api_usage
  SET last_export_at = now()
  WHERE user_id = @userId
    AND (last_export_at IS NULL OR last_export_at <= now() - interval '1 day')
  RETURNING user_id
)
SELECT EXISTS (SELECT 1 FROM _claim) AS claimed,
       (SELECT last_export_at FROM api_usage WHERE user_id = @userId) AS last_export_at
''';
