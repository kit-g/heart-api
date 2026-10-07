BEGIN;
SELECT plan(9);

SELECT has_table('public'::name, 'oauth_assertion_jtis'::name);
SELECT columns_are('public', 'oauth_assertion_jtis', ARRAY ['client_id', 'jti', 'expires_at']);
SELECT col_type_is('public'::name, 'oauth_assertion_jtis'::name, 'client_id'::name, 'text'::name);
SELECT col_type_is('public'::name, 'oauth_assertion_jtis'::name, 'jti'::name, 'text'::name);
SELECT col_type_is('public'::name, 'oauth_assertion_jtis'::name, 'expires_at'::name, 'timestamp with time zone'::name);
SELECT has_pk('public'::name, 'oauth_assertion_jtis'::name, 'oauth_assertion_jtis has a primary key');
SELECT col_is_pk('public', 'oauth_assertion_jtis', ARRAY ['client_id', 'jti'], 'one record per client and jti');
SELECT col_not_null('public'::name, 'oauth_assertion_jtis'::name, 'expires_at'::name);
SELECT col_not_null('public'::name, 'oauth_assertion_jtis'::name, 'jti'::name);

SELECT * FROM finish();
ROLLBACK;
