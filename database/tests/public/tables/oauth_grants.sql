BEGIN;

SELECT plan(23);

SELECT has_table('public'::name, 'oauth_grants'::name);

SELECT columns_are(
               'public',
               'oauth_grants',
               ARRAY [
                   'id',
                   'user_id',
                   'client_id',
                   'client_name',
                   'scopes',
                   'resource',
                   'created_at',
                   'last_used_at',
                   'revoked_at'
                   ]
       );

SELECT col_type_is('public'::name, 'oauth_grants'::name, 'id'::name, 'uuid'::name);
SELECT col_type_is('public'::name, 'oauth_grants'::name, 'user_id'::name, 'text'::name);
SELECT col_type_is('public'::name, 'oauth_grants'::name, 'client_id'::name, 'text'::name);
SELECT col_type_is('public'::name, 'oauth_grants'::name, 'client_name'::name, 'text'::name);
SELECT col_type_is('public'::name, 'oauth_grants'::name, 'scopes'::name, 'text[]'::name);
SELECT col_type_is('public'::name, 'oauth_grants'::name, 'resource'::name, 'text'::name);
SELECT col_type_is('public'::name, 'oauth_grants'::name, 'created_at'::name, 'timestamp with time zone'::name);
SELECT col_type_is('public'::name, 'oauth_grants'::name, 'last_used_at'::name, 'timestamp with time zone'::name);
SELECT col_type_is('public'::name, 'oauth_grants'::name, 'revoked_at'::name, 'timestamp with time zone'::name);

SELECT col_is_pk('public'::name, 'oauth_grants'::name, 'id'::name);

SELECT col_not_null('public'::name, 'oauth_grants'::name, 'user_id'::name);
SELECT col_not_null('public'::name, 'oauth_grants'::name, 'client_id'::name);
SELECT col_not_null('public'::name, 'oauth_grants'::name, 'client_name'::name);
SELECT col_not_null('public'::name, 'oauth_grants'::name, 'scopes'::name);
SELECT col_not_null('public'::name, 'oauth_grants'::name, 'resource'::name);
SELECT col_not_null('public'::name, 'oauth_grants'::name, 'created_at'::name);

SELECT col_default_is('public', 'oauth_grants', 'id', 'uuidv7()', 'id default is uuidv7()');
SELECT col_default_is('public', 'oauth_grants', 'created_at', 'now()', 'created_at defaults to now()');

SELECT fk_ok('public', 'oauth_grants', 'user_id', 'public', 'profiles', 'id');

SELECT has_index('public'::name, 'oauth_grants'::name, 'oauth_grants_live_idx'::name);
SELECT index_is_unique('public'::name, 'oauth_grants'::name, 'oauth_grants_live_idx'::name);

SELECT * FROM finish();

ROLLBACK;
