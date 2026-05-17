BEGIN;

SELECT plan(20);

SELECT has_table('public'::name, 'device_tokens'::name);

SELECT columns_are(
               'public',
               'device_tokens',
               ARRAY [
                   'id',
                   'profile_id',
                   'platform',
                   'token',
                   'locale',
                   'settings',
                   'created_at',
                   'last_seen_at'
                   ]
       );

SELECT col_type_is('public'::name, 'device_tokens'::name, 'id'::name, 'uuid'::name);
SELECT col_type_is('public'::name, 'device_tokens'::name, 'profile_id'::name, 'text'::name);
SELECT col_type_is('public'::name, 'device_tokens'::name, 'platform'::name, 'text'::name);
SELECT col_type_is('public'::name, 'device_tokens'::name, 'token'::name, 'text'::name);
SELECT col_type_is('public'::name, 'device_tokens'::name, 'locale'::name, 'text'::name);
SELECT col_type_is('public'::name, 'device_tokens'::name, 'settings'::name, 'jsonb'::name);

SELECT has_pk('public'::name, 'device_tokens'::name);
SELECT col_is_pk('public'::name, 'device_tokens'::name, 'id'::name);
SELECT col_is_unique('public'::name, 'device_tokens'::name, 'token'::name);

SELECT col_not_null('public'::name, 'device_tokens'::name, 'profile_id'::name);
SELECT col_not_null('public'::name, 'device_tokens'::name, 'platform'::name);
SELECT col_not_null('public'::name, 'device_tokens'::name, 'token'::name);
SELECT col_not_null('public'::name, 'device_tokens'::name, 'locale'::name);
SELECT col_not_null('public'::name, 'device_tokens'::name, 'settings'::name);

SELECT col_default_is('public', 'device_tokens', 'id', 'uuidv7()', 'id default is uuidv7()');
SELECT col_default_is('public', 'device_tokens', 'locale', 'en', 'locale default is en');
SELECT col_default_is('public', 'device_tokens', 'settings', '{}'::jsonb, 'settings default is empty jsonb');

SELECT fk_ok('public', 'device_tokens', 'profile_id', 'public', 'profiles', 'id');

SELECT * FROM finish();

ROLLBACK;
