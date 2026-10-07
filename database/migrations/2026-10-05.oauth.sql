-- An OAuth 2.1 authorization server on top of the existing accounts
-- (heart-api#115): the clients that may ask for access, the authorization
-- requests in flight, the grants users gave, and the refresh tokens that keep
-- them alive. Access tokens are api_tokens rows tied to a grant.

DROP TABLE IF EXISTS oauth_refresh_tokens;
DROP TABLE IF EXISTS oauth_requests;

DROP TABLE IF EXISTS oauth_clients;
CREATE TABLE IF NOT EXISTS oauth_clients
(
    client_id                  TEXT PRIMARY KEY,
    kind                       TEXT        NOT NULL CHECK (kind IN ('cimd', 'dcr')),
    client_name                TEXT,
    redirect_uris              TEXT[]      NOT NULL,
    token_endpoint_auth_method TEXT        NOT NULL DEFAULT 'none',
    jwks_uri                   TEXT,
    metadata                   JSONB       NOT NULL DEFAULT '{}'::jsonb,
    fetched_at                 TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at                 TIMESTAMPTZ,
    last_used_at               TIMESTAMPTZ
);

COMMENT ON TABLE oauth_clients IS
    'Clients that may request authorization: metadata documents fetched from their client_id URL (cimd), or dynamic registrations (dcr)';
COMMENT ON COLUMN oauth_clients.client_id IS
    'For cimd, the HTTPS URL of the client''s metadata document; for dcr, an id minted at registration';
COMMENT ON COLUMN oauth_clients.kind IS
    'cimd (Client ID Metadata Document) or dcr (RFC 7591 dynamic registration)';
COMMENT ON COLUMN oauth_clients.client_name IS
    'The name the client gives itself; shown on consent beside its redirect host, never trusted alone';
COMMENT ON COLUMN oauth_clients.redirect_uris IS
    'Where authorization responses may go; matched exactly, except loopback hosts, which match on any port';
COMMENT ON COLUMN oauth_clients.token_endpoint_auth_method IS
    'none (a public client, PKCE only) or private_key_jwt (signs an assertion with a key from jwks_uri)';
COMMENT ON COLUMN oauth_clients.jwks_uri IS
    'Where a private_key_jwt client publishes its signing keys';
COMMENT ON COLUMN oauth_clients.metadata IS
    'The metadata document or registration request as received, snake_case keys per RFC 7591';
COMMENT ON COLUMN oauth_clients.fetched_at IS
    'When the cimd document was last fetched, or the dcr registration made';
COMMENT ON COLUMN oauth_clients.expires_at IS
    'When a cached cimd document must be fetched again; NULL for dcr';
COMMENT ON COLUMN oauth_clients.last_used_at IS
    'Last authorization by this client; a dcr registration never used is garbage';

CREATE TABLE IF NOT EXISTS oauth_requests
(
    id              UUID        DEFAULT uuidv7() PRIMARY KEY,
    client_id       TEXT        NOT NULL REFERENCES oauth_clients (client_id) ON DELETE CASCADE,
    redirect_uri    TEXT        NOT NULL,
    code_challenge  TEXT        NOT NULL,
    scopes          TEXT[]      NOT NULL,
    resource        TEXT        NOT NULL,
    state           TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at      TIMESTAMPTZ NOT NULL,
    user_id         TEXT REFERENCES profiles (id) ON DELETE CASCADE,
    code_hash       BYTEA UNIQUE,
    code_expires_at TIMESTAMPTZ,
    used_at         TIMESTAMPTZ
);

COMMENT ON TABLE oauth_requests IS
    'Authorization requests from /authorize to consent, and the single-use code an approved one mints';
COMMENT ON COLUMN oauth_requests.code_challenge IS
    'PKCE S256 challenge: base64url(sha256(code_verifier))';
COMMENT ON COLUMN oauth_requests.scopes IS
    'What the client asked for';
COMMENT ON COLUMN oauth_requests.resource IS
    'The RFC 8707 resource the resulting tokens are bound to';
COMMENT ON COLUMN oauth_requests.state IS
    'The client''s state, echoed back on the redirect';
COMMENT ON COLUMN oauth_requests.expires_at IS
    'How long the user has to answer the consent screen';
COMMENT ON COLUMN oauth_requests.user_id IS
    'The account that approved; NULL until then';
COMMENT ON COLUMN oauth_requests.code_hash IS
    'sha256 of the authorization code minted on approval; the code itself is never stored';
COMMENT ON COLUMN oauth_requests.code_expires_at IS
    'The code is good for a minute';
COMMENT ON COLUMN oauth_requests.used_at IS
    'When the code was exchanged; a code is single use';

CREATE INDEX IF NOT EXISTS oauth_requests_expires_idx ON oauth_requests (expires_at);

COMMENT ON INDEX oauth_requests_expires_idx IS
    'Finding stale requests to clear';

DROP TABLE IF EXISTS oauth_grants CASCADE;
CREATE TABLE IF NOT EXISTS oauth_grants
(
    id           UUID        DEFAULT uuidv7() PRIMARY KEY,
    user_id      TEXT        NOT NULL REFERENCES profiles (id) ON DELETE CASCADE,
    client_id    TEXT        NOT NULL,
    client_name  TEXT        NOT NULL,
    scopes       TEXT[]      NOT NULL,
    resource     TEXT        NOT NULL,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_used_at TIMESTAMPTZ,
    revoked_at   TIMESTAMPTZ
);

COMMENT ON TABLE oauth_grants IS
    'One account''s consent to one client for one resource: what the account sees as a connected app and can revoke';
COMMENT ON COLUMN oauth_grants.client_id IS
    'The client, by id; no foreign key, so a re-fetched or expired client document never takes a grant with it';
COMMENT ON COLUMN oauth_grants.client_name IS
    'The client''s name as shown on the consent screen, frozen at that moment';
COMMENT ON COLUMN oauth_grants.scopes IS
    'What was granted; approving the same client again widens it';
COMMENT ON COLUMN oauth_grants.resource IS
    'The resource its tokens are bound to';
COMMENT ON COLUMN oauth_grants.last_used_at IS
    'Last token issued under the grant';
COMMENT ON COLUMN oauth_grants.revoked_at IS
    'When the account disconnected the client, or a reused refresh token gave the grant away';

CREATE UNIQUE INDEX IF NOT EXISTS oauth_grants_live_idx
    ON oauth_grants (user_id, client_id, resource) WHERE revoked_at IS NULL;

COMMENT ON INDEX oauth_grants_live_idx IS
    'At most one live grant per account, client and resource';

CREATE TABLE IF NOT EXISTS oauth_refresh_tokens
(
    token_hash BYTEA PRIMARY KEY,
    grant_id   UUID        NOT NULL REFERENCES oauth_grants (id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL,
    rotated_at TIMESTAMPTZ
);

COMMENT ON TABLE oauth_refresh_tokens IS
    'Refresh tokens by sha256; each is exchanged once for the next';
COMMENT ON COLUMN oauth_refresh_tokens.expires_at IS
    'Ninety days after issue: a host unused that long asks the account again';
COMMENT ON COLUMN oauth_refresh_tokens.rotated_at IS
    'When it was exchanged; presenting it again means someone else holds a copy';

CREATE INDEX IF NOT EXISTS oauth_refresh_tokens_grant_idx ON oauth_refresh_tokens (grant_id);

COMMENT ON INDEX oauth_refresh_tokens_grant_idx IS
    'A grant''s refresh tokens, for revoking them together';

-- Access tokens are api_tokens rows. These two columns tie a row to the grant
-- that issued it; dropping them on a replay would turn every OAuth token into
-- a personal one, so they are only ever added.
ALTER TABLE IF EXISTS api_tokens
    ADD COLUMN IF NOT EXISTS grant_id UUID,
    ADD COLUMN IF NOT EXISTS resource TEXT;

-- Declared apart from the column: replaying this file drops oauth_grants
-- with CASCADE, which takes the constraint and leaves the column.
ALTER TABLE IF EXISTS api_tokens
    DROP CONSTRAINT IF EXISTS api_tokens_grant_fk,
    ADD CONSTRAINT api_tokens_grant_fk FOREIGN KEY (grant_id) REFERENCES oauth_grants (id) ON DELETE CASCADE;

COMMENT ON CONSTRAINT api_tokens_grant_fk ON api_tokens IS
    'Revoking a grant by deleting it takes its access tokens with it';

COMMENT ON COLUMN api_tokens.grant_id IS
    'The OAuth grant an access token was issued under; NULL for a personal token';
COMMENT ON COLUMN api_tokens.resource IS
    'The resource an OAuth access token is bound to; NULL for a personal token, which acts as its owner anywhere';

CREATE INDEX IF NOT EXISTS api_tokens_grant_idx ON api_tokens (grant_id) WHERE grant_id IS NOT NULL;

COMMENT ON INDEX api_tokens_grant_idx IS
    'A grant''s access tokens, for replacing or revoking them';
