BEGIN;

SELECT plan(14);

SELECT has_table('public'::name, 'oauth_refresh_tokens'::name);

SELECT columns_are(
               'public',
               'oauth_refresh_tokens',
               ARRAY [
                   'token_hash',
                   'grant_id',
                   'created_at',
                   'expires_at',
                   'rotated_at'
                   ]
       );

SELECT col_type_is('public'::name, 'oauth_refresh_tokens'::name, 'token_hash'::name, 'bytea'::name);
SELECT col_type_is('public'::name, 'oauth_refresh_tokens'::name, 'grant_id'::name, 'uuid'::name);
SELECT col_type_is('public'::name, 'oauth_refresh_tokens'::name, 'created_at'::name, 'timestamp with time zone'::name);
SELECT col_type_is('public'::name, 'oauth_refresh_tokens'::name, 'expires_at'::name, 'timestamp with time zone'::name);
SELECT col_type_is('public'::name, 'oauth_refresh_tokens'::name, 'rotated_at'::name, 'timestamp with time zone'::name);

SELECT col_is_pk('public'::name, 'oauth_refresh_tokens'::name, 'token_hash'::name);

SELECT col_not_null('public'::name, 'oauth_refresh_tokens'::name, 'grant_id'::name);
SELECT col_not_null('public'::name, 'oauth_refresh_tokens'::name, 'created_at'::name);
SELECT col_not_null('public'::name, 'oauth_refresh_tokens'::name, 'expires_at'::name);

SELECT col_default_is('public', 'oauth_refresh_tokens', 'created_at', 'now()', 'created_at defaults to now()');

SELECT fk_ok('public', 'oauth_refresh_tokens', 'grant_id', 'public', 'oauth_grants', 'id');
SELECT has_index('public'::name, 'oauth_refresh_tokens'::name, 'oauth_refresh_tokens_grant_idx'::name);

SELECT * FROM finish();

ROLLBACK;
