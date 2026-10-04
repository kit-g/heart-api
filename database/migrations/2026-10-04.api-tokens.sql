-- Personal access tokens for the developer API, and the per-account counters
-- that rate-limit them (heart-api#111).
--
-- A token is stored only as the sha256 of its secret: the secret carries 256
-- bits of entropy, so a plain digest is as strong as a slow hash and keeps the
-- lookup a single indexed equality. Revoked rows are kept, not deleted, so an
-- account's token history stays answerable.

DROP TABLE IF EXISTS api_tokens;
CREATE TABLE IF NOT EXISTS api_tokens
(
    id           UUID        DEFAULT uuidv7() PRIMARY KEY,
    user_id      TEXT        NOT NULL REFERENCES profiles (id) ON DELETE CASCADE,
    name         TEXT        NOT NULL,
    purpose      TEXT,
    token_hash   BYTEA       NOT NULL UNIQUE,
    hint         TEXT        NOT NULL,
    scopes       TEXT[]      NOT NULL DEFAULT '{read}',
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_used_at TIMESTAMPTZ,
    expires_at   TIMESTAMPTZ,
    revoked_at   TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS api_tokens_user_id_idx ON api_tokens (user_id);

COMMENT ON TABLE api_tokens IS
    'Personal access tokens: bearer credentials an account mints for itself, to read its own data from scripts and assistants';
COMMENT ON COLUMN api_tokens.user_id IS
    'The account the token acts as; deleting the profile deletes its tokens';
COMMENT ON COLUMN api_tokens.name IS
    'Owner-chosen label ("my sheet", "Home Assistant")';
COMMENT ON COLUMN api_tokens.purpose IS
    'What the owner said the token is for, if anything; a camelCase enum value, unchecked here so the list can grow';
COMMENT ON COLUMN api_tokens.token_hash IS
    'sha256 of the secret; the secret itself is never stored';
COMMENT ON COLUMN api_tokens.hint IS
    'Last four characters of the secret, so the owner can match a token to where it was pasted';
COMMENT ON COLUMN api_tokens.scopes IS
    'What the token may do; read-only by default';
COMMENT ON COLUMN api_tokens.last_used_at IS
    'Set on every authenticated use; NULL until first used';
COMMENT ON COLUMN api_tokens.expires_at IS
    'NULL when the token lives until revoked';
COMMENT ON COLUMN api_tokens.revoked_at IS
    'When the owner revoked it; a revoked token never authenticates again';

DROP TABLE IF EXISTS api_usage;
CREATE TABLE IF NOT EXISTS api_usage
(
    user_id      TEXT PRIMARY KEY REFERENCES profiles (id) ON DELETE CASCADE,
    minute_start TIMESTAMPTZ,
    minute_count INTEGER NOT NULL DEFAULT 0,
    day_start    TIMESTAMPTZ,
    day_count    INTEGER NOT NULL DEFAULT 0
);

COMMENT ON TABLE api_usage IS
    'Per-account request counters for the token-authenticated surface, in two fixed windows. Counting only: limits and entitlements live elsewhere';
COMMENT ON COLUMN api_usage.minute_start IS
    'Start of the current one-minute window, which shapes bursts';
COMMENT ON COLUMN api_usage.minute_count IS
    'Requests counted since minute_start';
COMMENT ON COLUMN api_usage.day_start IS
    'Start of the current 24-hour window, which bounds cost';
COMMENT ON COLUMN api_usage.day_count IS
    'Requests counted since day_start';
