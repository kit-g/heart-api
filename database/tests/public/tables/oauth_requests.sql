BEGIN;

SELECT plan(29);

SELECT has_table('public'::name, 'oauth_requests'::name);

SELECT columns_are(
               'public',
               'oauth_requests',
               ARRAY [
                   'id',
                   'client_id',
                   'redirect_uri',
                   'code_challenge',
                   'scopes',
                   'resource',
                   'state',
                   'created_at',
                   'expires_at',
                   'user_id',
                   'code_hash',
                   'code_expires_at',
                   'used_at'
                   ]
       );

SELECT col_type_is('public'::name, 'oauth_requests'::name, 'id'::name, 'uuid'::name);
SELECT col_type_is('public'::name, 'oauth_requests'::name, 'client_id'::name, 'text'::name);
SELECT col_type_is('public'::name, 'oauth_requests'::name, 'redirect_uri'::name, 'text'::name);
SELECT col_type_is('public'::name, 'oauth_requests'::name, 'code_challenge'::name, 'text'::name);
SELECT col_type_is('public'::name, 'oauth_requests'::name, 'scopes'::name, 'text[]'::name);
SELECT col_type_is('public'::name, 'oauth_requests'::name, 'resource'::name, 'text'::name);
SELECT col_type_is('public'::name, 'oauth_requests'::name, 'state'::name, 'text'::name);
SELECT col_type_is('public'::name, 'oauth_requests'::name, 'created_at'::name, 'timestamp with time zone'::name);
SELECT col_type_is('public'::name, 'oauth_requests'::name, 'expires_at'::name, 'timestamp with time zone'::name);
SELECT col_type_is('public'::name, 'oauth_requests'::name, 'user_id'::name, 'text'::name);
SELECT col_type_is('public'::name, 'oauth_requests'::name, 'code_hash'::name, 'bytea'::name);
SELECT col_type_is('public'::name, 'oauth_requests'::name, 'code_expires_at'::name, 'timestamp with time zone'::name);
SELECT col_type_is('public'::name, 'oauth_requests'::name, 'used_at'::name, 'timestamp with time zone'::name);

SELECT col_is_pk('public'::name, 'oauth_requests'::name, 'id'::name);

SELECT col_not_null('public'::name, 'oauth_requests'::name, 'client_id'::name);
SELECT col_not_null('public'::name, 'oauth_requests'::name, 'redirect_uri'::name);
SELECT col_not_null('public'::name, 'oauth_requests'::name, 'code_challenge'::name);
SELECT col_not_null('public'::name, 'oauth_requests'::name, 'scopes'::name);
SELECT col_not_null('public'::name, 'oauth_requests'::name, 'resource'::name);
SELECT col_not_null('public'::name, 'oauth_requests'::name, 'created_at'::name);
SELECT col_not_null('public'::name, 'oauth_requests'::name, 'expires_at'::name);

SELECT col_default_is('public', 'oauth_requests', 'id', 'uuidv7()', 'id default is uuidv7()');
SELECT col_default_is('public', 'oauth_requests', 'created_at', 'now()', 'created_at defaults to now()');

SELECT fk_ok('public', 'oauth_requests', 'client_id', 'public', 'oauth_clients', 'client_id');
SELECT fk_ok('public', 'oauth_requests', 'user_id', 'public', 'profiles', 'id');

SELECT col_is_unique('public'::name, 'oauth_requests'::name, 'code_hash'::name);
SELECT has_index('public'::name, 'oauth_requests'::name, 'oauth_requests_expires_idx'::name);

SELECT * FROM finish();

ROLLBACK;
