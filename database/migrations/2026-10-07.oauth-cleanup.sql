-- The OAuth tables' garbage collection, as a function pg_cron calls daily.
-- Live connections prune their own tokens on every refresh; this clears what
-- nothing will touch again. Personal access tokens are never touched.

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
    'Deletes OAuth rows no flow can use: expired requests and tokens, grants revoked over 30 days ago, expired client documents, idle registrations. Returns how many of each went';
