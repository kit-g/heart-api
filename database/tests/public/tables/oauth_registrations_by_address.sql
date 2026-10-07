BEGIN;
SELECT plan(9);

SELECT has_table('public'::name, 'oauth_registrations_by_address'::name);
SELECT columns_are('public', 'oauth_registrations_by_address', ARRAY ['day', 'address_hash', 'count']);
SELECT col_type_is('public'::name, 'oauth_registrations_by_address'::name, 'day'::name, 'date'::name);
SELECT col_type_is('public'::name, 'oauth_registrations_by_address'::name, 'address_hash'::name, 'bytea'::name);
SELECT col_type_is('public'::name, 'oauth_registrations_by_address'::name, 'count'::name, 'integer'::name);
SELECT has_pk('public'::name, 'oauth_registrations_by_address'::name, 'oauth_registrations_by_address has a primary key');
SELECT col_is_pk('public', 'oauth_registrations_by_address', ARRAY ['day', 'address_hash'], 'one count per day and address');
SELECT col_not_null('public'::name, 'oauth_registrations_by_address'::name, 'count'::name);
SELECT col_default_is('public', 'oauth_registrations_by_address', 'count', 1, 'a first registration counts one');

SELECT * FROM finish();
ROLLBACK;
