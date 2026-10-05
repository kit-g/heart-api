-- The index api_tokens shipped with (2026-10-04.api-tokens.sql) went out
-- without a comment; that migration has run, so it gets one here.

COMMENT ON INDEX api_tokens_user_id_idx IS
    'An account''s tokens, for listing them and counting the active ones';
