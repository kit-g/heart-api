BEGIN;

SELECT plan(22);

SELECT has_table('public'::name, 'oauth_clients'::name);

SELECT columns_are(
               'public',
               'oauth_clients',
               ARRAY [
                   'client_id',
                   'kind',
                   'client_name',
                   'redirect_uris',
                   'token_endpoint_auth_method',
                   'jwks_uri',
                   'metadata',
                   'fetched_at',
                   'expires_at',
                   'last_used_at'
                   ]
       );

SELECT col_type_is('public'::name, 'oauth_clients'::name, 'client_id'::name, 'text'::name);
SELECT col_type_is('public'::name, 'oauth_clients'::name, 'kind'::name, 'text'::name);
SELECT col_type_is('public'::name, 'oauth_clients'::name, 'client_name'::name, 'text'::name);
SELECT col_type_is('public'::name, 'oauth_clients'::name, 'redirect_uris'::name, 'text[]'::name);
SELECT col_type_is('public'::name, 'oauth_clients'::name, 'token_endpoint_auth_method'::name, 'text'::name);
SELECT col_type_is('public'::name, 'oauth_clients'::name, 'jwks_uri'::name, 'text'::name);
SELECT col_type_is('public'::name, 'oauth_clients'::name, 'metadata'::name, 'jsonb'::name);
SELECT col_type_is('public'::name, 'oauth_clients'::name, 'fetched_at'::name, 'timestamp with time zone'::name);
SELECT col_type_is('public'::name, 'oauth_clients'::name, 'expires_at'::name, 'timestamp with time zone'::name);
SELECT col_type_is('public'::name, 'oauth_clients'::name, 'last_used_at'::name, 'timestamp with time zone'::name);

SELECT col_is_pk('public'::name, 'oauth_clients'::name, 'client_id'::name);

SELECT col_not_null('public'::name, 'oauth_clients'::name, 'kind'::name);
SELECT col_not_null('public'::name, 'oauth_clients'::name, 'redirect_uris'::name);
SELECT col_not_null('public'::name, 'oauth_clients'::name, 'token_endpoint_auth_method'::name);
SELECT col_not_null('public'::name, 'oauth_clients'::name, 'metadata'::name);
SELECT col_not_null('public'::name, 'oauth_clients'::name, 'fetched_at'::name);

SELECT col_default_is('public', 'oauth_clients', 'token_endpoint_auth_method', 'none', 'public clients by default');
SELECT col_default_is('public', 'oauth_clients', 'metadata', '{}'::jsonb, 'metadata defaults to empty');
SELECT col_default_is('public', 'oauth_clients', 'fetched_at', 'now()', 'fetched_at defaults to now()');

SELECT has_check('public'::name, 'oauth_clients'::name, 'kind is cimd or dcr');

SELECT * FROM finish();

ROLLBACK;
