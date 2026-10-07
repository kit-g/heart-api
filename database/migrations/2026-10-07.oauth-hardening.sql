-- OAuth hardening: an assertion can't be replayed, and registrations are
-- counted per source address without storing any address. The cleanup sweeps
-- both.

DROP TABLE IF EXISTS oauth_assertion_jtis;
CREATE TABLE IF NOT EXISTS oauth_assertion_jtis
(
    client_id  TEXT        NOT NULL,
    jti        TEXT        NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (client_id, jti)
);

COMMENT ON TABLE oauth_assertion_jtis IS
    'Client assertions (private_key_jwt) already used, kept until they expire, so none is used twice';
COMMENT ON COLUMN oauth_assertion_jtis.client_id IS 'The client the assertion authenticated';
COMMENT ON COLUMN oauth_assertion_jtis.jti IS 'The assertion''s own id (its jti claim)';
COMMENT ON COLUMN oauth_assertion_jtis.expires_at IS 'The assertion''s expiry; past it, it would be refused anyway';

DROP TABLE IF EXISTS oauth_address_salts;
CREATE TABLE IF NOT EXISTS oauth_address_salts
(
    day  DATE  PRIMARY KEY,
    salt BYTEA NOT NULL
);

COMMENT ON TABLE oauth_address_salts IS
    'A random salt per day for hashing source addresses; deleted after two days, which unlinks that day''s hashes';
COMMENT ON COLUMN oauth_address_salts.day IS 'The UTC day the salt hashes';
COMMENT ON COLUMN oauth_address_salts.salt IS '16 random bytes';

DROP TABLE IF EXISTS oauth_registrations_by_address;
CREATE TABLE IF NOT EXISTS oauth_registrations_by_address
(
    day          DATE    NOT NULL,
    address_hash BYTEA   NOT NULL,
    count        INTEGER NOT NULL DEFAULT 1,
    PRIMARY KEY (day, address_hash)
);

COMMENT ON TABLE oauth_registrations_by_address IS
    'Dynamic client registrations per source address per day, keyed by a salted hash: no address is stored';
COMMENT ON COLUMN oauth_registrations_by_address.day IS 'The UTC day counted';
COMMENT ON COLUMN oauth_registrations_by_address.address_hash IS 'sha256 of that day''s salt and the source address';
COMMENT ON COLUMN oauth_registrations_by_address.count IS 'Registrations from that address that day';

DROP FUNCTION IF EXISTS _clean_up_oauth();

CREATE OR REPLACE FUNCTION _clean_up_oauth()
    RETURNS TABLE
            (
                requests       BIGINT,
                access_tokens  BIGINT,
                refresh_tokens BIGINT,
                grants         BIGINT,
                documents      BIGINT,
                registrations  BIGINT
            )
    LANGUAGE sql
AS
$$
WITH _requests AS (
    -- a request and its code, a day after both expired
    DELETE FROM oauth_requests
    WHERE greatest(expires_at, coalesce(code_expires_at, expires_at)) < now() - interval '1 day'
    RETURNING client_id
), _grants AS (
    -- revoked grants are kept 30 days, so a reuse revocation can be looked into
    DELETE FROM oauth_grants
    WHERE revoked_at < now() - interval '30 days'
    RETURNING id
), _access AS (
    DELETE FROM api_tokens
    WHERE grant_id IS NOT NULL
    AND grant_id NOT IN (SELECT id FROM _grants)
    AND expires_at < now()
    RETURNING id
), _refresh AS (
    -- rotated tokens stay the week the reuse check needs them
    DELETE FROM oauth_refresh_tokens
    WHERE grant_id NOT IN (SELECT id FROM _grants)
    AND (expires_at < now() OR rotated_at < now() - interval '7 days')
    RETURNING token_hash
), _clients AS (
    -- a client with a request in flight waits for the next run; a cached
    -- metadata document is refetched on its next use; a registration can't
    -- be, so it goes only after 30 days with no use and no live grant
    DELETE FROM oauth_clients c
    WHERE NOT EXISTS (SELECT 1 FROM oauth_requests r WHERE r.client_id = c.client_id)
    AND CASE c.kind
        WHEN 'cimd' THEN c.expires_at < now()
        ELSE coalesce(c.last_used_at, c.fetched_at) < now() - interval '30 days'
            AND NOT EXISTS (
                SELECT 1 FROM oauth_grants g WHERE g.client_id = c.client_id AND g.revoked_at IS NULL
            )
    END
    RETURNING kind
), _assertions AS (
    DELETE FROM oauth_assertion_jtis
    WHERE expires_at < now()
    RETURNING jti
), _salts AS (
    -- once a day's salt is gone, its address hashes can't be linked to anyone
    DELETE FROM oauth_address_salts
    WHERE day < current_date - 1
    RETURNING day
), _addresses AS (
    DELETE FROM oauth_registrations_by_address
    WHERE day < current_date - 1
    RETURNING day
)
SELECT
    (SELECT count(*) FROM _requests),
    (SELECT count(*) FROM _access),
    (SELECT count(*) FROM _refresh),
    (SELECT count(*) FROM _grants),
    (SELECT count(*) FROM _clients WHERE kind = 'cimd'),
    (SELECT count(*) FROM _clients WHERE kind = 'dcr')
$$;

COMMENT ON FUNCTION _clean_up_oauth() IS
    'Deletes OAuth rows no flow can use: expired requests, tokens and assertions, grants revoked over 30 days ago, expired client documents, idle registrations, and address counts and salts past a day. Returns how many of the first six went';
