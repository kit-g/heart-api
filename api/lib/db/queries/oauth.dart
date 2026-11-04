part of '../db.dart';

const _getOAuthClient = '''
SELECT client_id, kind, client_name, redirect_uris, token_endpoint_auth_method, jwks_uri, expires_at
FROM oauth_clients
WHERE client_id = @clientId
''';

const _saveOAuthClient = '''
INSERT INTO oauth_clients
  (client_id, kind, client_name, redirect_uris, token_endpoint_auth_method, jwks_uri, metadata, expires_at)
VALUES (@clientId, 'cimd', @name, @redirectUris, @auth, @jwksUri, @metadata::jsonb, @expiresAt)
ON CONFLICT (client_id) DO UPDATE
SET client_name                = excluded.client_name,
    redirect_uris              = excluded.redirect_uris,
    token_endpoint_auth_method = excluded.token_endpoint_auth_method,
    jwks_uri                   = excluded.jwks_uri,
    metadata                   = excluded.metadata,
    fetched_at                 = now(),
    expires_at                 = excluded.expires_at
RETURNING client_id, kind, client_name, redirect_uris, token_endpoint_auth_method, jwks_uri, expires_at
''';

const _registerOAuthClient = '''
INSERT INTO oauth_clients (client_id, kind, client_name, redirect_uris, token_endpoint_auth_method, jwks_uri, metadata)
VALUES ('dcr_' || uuidv7(), 'dcr', @name, @redirectUris, @auth, @jwksUri, @metadata::jsonb)
RETURNING client_id, kind, client_name, redirect_uris, token_endpoint_auth_method, jwks_uri, expires_at
''';

const _createOAuthRequest = '''
WITH _request AS (
  INSERT INTO oauth_requests (client_id, redirect_uri, code_challenge, scopes, resource, state, expires_at)
  VALUES (
    @clientId, @redirectUri, @codeChallenge, @scopes, @resource, @state,
    now() + make_interval(secs => @ttlSeconds)
  )
  RETURNING id, client_id
), _client AS (
  UPDATE oauth_clients
  SET last_used_at = now()
  WHERE client_id IN (SELECT client_id FROM _request)
  RETURNING client_id
)
SELECT id FROM _request
''';

const _getPendingOAuthRequest = '''
SELECT r.id, r.client_id, c.client_name, r.redirect_uri, r.scopes, r.resource, r.state
FROM oauth_requests r
JOIN oauth_clients c USING (client_id)
WHERE r.id = @requestId::uuid
  AND r.user_id IS NULL
  AND r.expires_at > now()
''';

// Approving records the account's consent: a new grant, or the live one for
// the same client and resource widened by what this request asked for.
const _approveOAuthRequest = '''
WITH _request AS (
  UPDATE oauth_requests
  SET user_id = @userId,
      code_hash = @codeHash::bytea,
      code_expires_at = now() + make_interval(secs => @codeTtlSeconds)
  WHERE id = @requestId::uuid
    AND user_id IS NULL
    AND expires_at > now()
  RETURNING id, client_id, redirect_uri, scopes, resource, state
), _named AS (
  SELECT r.*, coalesce(c.client_name, r.client_id) AS client_name
  FROM _request r
  JOIN oauth_clients c USING (client_id)
), _grant AS (
  INSERT INTO oauth_grants (user_id, client_id, client_name, scopes, resource)
  SELECT @userId, client_id, client_name, scopes, resource FROM _named
  ON CONFLICT (user_id, client_id, resource) WHERE revoked_at IS NULL DO UPDATE
  SET
    scopes = ARRAY(
      SELECT DISTINCT s FROM unnest(oauth_grants.scopes || excluded.scopes) s ORDER BY s
    ),
    client_name = excluded.client_name
  RETURNING id
)
SELECT id, client_id, client_name, redirect_uri, scopes, resource, state
FROM _named
WHERE EXISTS (SELECT 1 FROM _grant)
''';

const _denyOAuthRequest = '''
WITH _request AS (
  DELETE FROM oauth_requests
  WHERE id = @requestId::uuid
    AND user_id IS NULL
  RETURNING id, client_id, redirect_uri, scopes, resource, state
)
SELECT r.id, r.client_id, c.client_name, r.redirect_uri, r.scopes, r.resource, r.state
FROM _request r
JOIN oauth_clients c USING (client_id)
''';

// A code is single use: spending it is the same statement that reads it. A
// code presented again after it was spent means a copy exists (RFC 6749
// §4.1.2): the grant it issued under is revoked with every token under it,
// and the replay itself gets nothing.
const _redeemOAuthCode = '''
WITH _code AS (
  SELECT id, user_id, client_id, resource, used_at
  FROM oauth_requests
  WHERE code_hash = @codeHash::bytea
  FOR UPDATE
), _redeemed AS (
  UPDATE oauth_requests r
  SET used_at = now()
  FROM _code c
  WHERE r.id = c.id
    AND c.used_at IS NULL
    AND r.code_expires_at > now()
  RETURNING r.user_id, r.client_id, r.redirect_uri, r.code_challenge, r.scopes, r.resource
), _replayed AS (
  UPDATE oauth_grants g
  SET revoked_at = now()
  FROM _code c
  WHERE c.used_at IS NOT NULL
    AND g.user_id = c.user_id
    AND g.client_id = c.client_id
    AND g.resource = c.resource
    AND g.revoked_at IS NULL
  RETURNING g.id
), _replayed_access AS (
  DELETE FROM api_tokens WHERE grant_id IN (SELECT id FROM _replayed) RETURNING id
), _replayed_refresh AS (
  DELETE FROM oauth_refresh_tokens WHERE grant_id IN (SELECT id FROM _replayed) RETURNING token_hash
)
SELECT * FROM _redeemed
''';

// A client assertion's jti, recorded until the assertion expires. Nothing
// comes back when it was already there: that assertion was used before.
const _rememberOAuthAssertion = '''
INSERT INTO oauth_assertion_jtis (client_id, jti, expires_at)
VALUES (@clientId, @jti, @expiresAt)
ON CONFLICT (client_id, jti) DO NOTHING
RETURNING jti
''';

// One more registration from a source address today, and how many that makes.
// The address is hashed with the day's salt, made on first use; no address is
// stored.
const _countOAuthRegistration = '''
WITH _salt AS (
  INSERT INTO oauth_address_salts (day, salt)
  VALUES (current_date, uuid_send(gen_random_uuid()))
  ON CONFLICT (day) DO UPDATE
  SET day = excluded.day
  RETURNING salt
), _count AS (
  INSERT INTO oauth_registrations_by_address (day, address_hash)
  SELECT current_date, sha256(salt || convert_to(@address, 'UTF8'))
  FROM _salt
  ON CONFLICT (day, address_hash) DO UPDATE
  SET count = oauth_registrations_by_address.count + 1
  RETURNING count
)
SELECT count FROM _count
''';

// Issues under the live grant. The grant's expired access tokens are cleared
// on the way; its live ones stay, since one account can run the same client
// on several devices.
const _issueOAuthTokens = '''
WITH _grant AS (
  SELECT id, user_id, client_name, resource
  FROM oauth_grants
  WHERE user_id = @userId
    AND client_id = @clientId
    AND resource = @resource
    AND revoked_at IS NULL
), _expired AS (
  DELETE FROM api_tokens
  WHERE grant_id IN (SELECT id FROM _grant)
    AND expires_at < now()
  RETURNING id
), _access AS (
  INSERT INTO api_tokens (user_id, name, token_hash, hint, scopes, expires_at, grant_id, resource)
  SELECT user_id, client_name, @accessHash::bytea, @accessHint, @scopes, @accessExpiresAt, id, resource
  FROM _grant
  RETURNING grant_id
), _refresh AS (
  INSERT INTO oauth_refresh_tokens (token_hash, grant_id, expires_at)
  SELECT @refreshHash::bytea, grant_id, @refreshExpiresAt FROM _access
  RETURNING grant_id
)
UPDATE oauth_grants
SET last_used_at = now()
WHERE id IN (SELECT grant_id FROM _refresh)
RETURNING id
''';

// Rotation, with reuse detection (RFC 9700): a refresh token presented after
// it was exchanged means a copy exists, so the whole grant goes. The row is
// locked, so two concurrent exchanges can't both rotate it. Within a minute
// of its rotation a second presentation is a host's parallel or retried
// refresh, not theft: it's refused without revoking. Rotated tokens are kept
// a week for the check, then cleared.
const _rotateOAuthRefresh = '''
WITH _old AS (
  SELECT
    r.token_hash, r.grant_id, r.rotated_at, r.expires_at,
    g.user_id, g.client_id, g.client_name, g.resource, g.revoked_at,
    (SELECT t.scopes FROM api_tokens t WHERE t.grant_id = g.id ORDER BY t.id DESC LIMIT 1) AS token_scopes,
    g.scopes AS grant_scopes
  FROM oauth_refresh_tokens r
  JOIN oauth_grants g ON g.id = r.grant_id
  WHERE r.token_hash = @refreshHash::bytea
    AND g.client_id = @clientId
  FOR UPDATE OF r
), _reused AS (
  UPDATE oauth_grants
  SET revoked_at = now()
  WHERE id IN (SELECT grant_id FROM _old WHERE rotated_at < now() - make_interval(secs => @graceSeconds))
    AND revoked_at IS NULL
  RETURNING id
), _reused_access AS (
  DELETE FROM api_tokens WHERE grant_id IN (SELECT id FROM _reused) RETURNING id
), _live AS (
  SELECT * FROM _old
  WHERE rotated_at IS NULL
    AND expires_at > now()
    AND revoked_at IS NULL
), _rotated AS (
  UPDATE oauth_refresh_tokens
  SET rotated_at = now()
  WHERE token_hash IN (SELECT token_hash FROM _live)
  RETURNING grant_id
), _stale AS (
  DELETE FROM oauth_refresh_tokens
  WHERE grant_id IN (SELECT grant_id FROM _rotated)
    AND rotated_at < now() - interval '7 days'
  RETURNING token_hash
), _expired AS (
  DELETE FROM api_tokens
  WHERE grant_id IN (SELECT grant_id FROM _rotated)
    AND expires_at < now()
  RETURNING id
), _access AS (
  INSERT INTO api_tokens (user_id, name, token_hash, hint, scopes, expires_at, grant_id, resource)
  SELECT
    l.user_id, l.client_name, @accessHash::bytea, @accessHint, coalesce(l.token_scopes, l.grant_scopes),
    @accessExpiresAt, l.grant_id, l.resource
  FROM _live l
  JOIN _rotated USING (grant_id)
  RETURNING grant_id, scopes
), _refresh AS (
  INSERT INTO oauth_refresh_tokens (token_hash, grant_id, expires_at)
  SELECT @newRefreshHash::bytea, grant_id, @refreshExpiresAt FROM _access
  RETURNING grant_id
), _touch AS (
  UPDATE oauth_grants
  SET last_used_at = now()
  WHERE id IN (SELECT grant_id FROM _refresh)
  RETURNING id
)
SELECT
  CASE
    WHEN EXISTS (SELECT 1 FROM _touch) THEN 'rotated'
    WHEN EXISTS (SELECT 1 FROM _reused) THEN 'reused'
    ELSE 'invalid'
  END AS outcome,
  (SELECT scopes FROM _access) AS scopes
''';

// RFC 7009: the client revokes one of its own tokens. An access token goes
// alone; a refresh token takes its whole grant.
const _revokeOAuthToken = '''
WITH _access AS (
  DELETE FROM api_tokens t
  USING oauth_grants g
  WHERE t.token_hash = @tokenHash::bytea
    AND t.grant_id = g.id
    AND g.client_id = @clientId
  RETURNING t.id
), _grant AS (
  UPDATE oauth_grants g
  SET revoked_at = now()
  FROM oauth_refresh_tokens r
  WHERE r.token_hash = @tokenHash::bytea
    AND r.grant_id = g.id
    AND g.client_id = @clientId
    AND g.revoked_at IS NULL
  RETURNING g.id
), _grant_access AS (
  DELETE FROM api_tokens WHERE grant_id IN (SELECT id FROM _grant) RETURNING id
), _grant_refresh AS (
  DELETE FROM oauth_refresh_tokens WHERE grant_id IN (SELECT id FROM _grant) RETURNING token_hash
)
SELECT (SELECT count(*) FROM _access) + (SELECT count(*) FROM _grant) AS revoked
''';

const _listConnectedApps = '''
SELECT id, client_id, client_name, scopes, resource, created_at, last_used_at
FROM oauth_grants
WHERE user_id = @userId
  AND revoked_at IS NULL
ORDER BY created_at DESC
''';

const _disconnectApp = '''
WITH _grant AS (
  UPDATE oauth_grants
  SET revoked_at = now()
  WHERE id = @grantId::uuid
    AND user_id = @userId
    AND revoked_at IS NULL
  RETURNING id
), _access AS (
  DELETE FROM api_tokens WHERE grant_id IN (SELECT id FROM _grant) RETURNING id
), _refresh AS (
  DELETE FROM oauth_refresh_tokens WHERE grant_id IN (SELECT id FROM _grant) RETURNING token_hash
)
SELECT id FROM _grant
''';

// Anomalies (heart-api#42). The sweep that finds them is _sweep_anomalies,
// run by pg_cron; these read and resolve them.
