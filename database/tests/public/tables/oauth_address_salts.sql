BEGIN;
SELECT plan(6);

SELECT has_table('public'::name, 'oauth_address_salts'::name);
SELECT columns_are('public', 'oauth_address_salts', ARRAY ['day', 'salt']);
SELECT col_type_is('public'::name, 'oauth_address_salts'::name, 'day'::name, 'date'::name);
SELECT col_type_is('public'::name, 'oauth_address_salts'::name, 'salt'::name, 'bytea'::name);
SELECT col_is_pk('public'::name, 'oauth_address_salts'::name, 'day'::name, 'one salt per day');
SELECT col_not_null('public'::name, 'oauth_address_salts'::name, 'salt'::name);

SELECT * FROM finish();
ROLLBACK;
