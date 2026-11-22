BEGIN;

SELECT plan(26);

SELECT has_table('public'::name, 'device_tokens'::name);

SELECT columns_are(
               'public',
               'device_tokens',
               ARRAY [
                   'profile_id',
                   'platform',
                   'token',
                   'locale',
                   'settings',
                   'created_at',
                   'last_seen_at',
                   'utc_offset_minutes'
                   ]
       );

SELECT col_type_is('public'::name, 'device_tokens'::name, 'profile_id'::name, 'text'::name);
SELECT col_type_is('public'::name, 'device_tokens'::name, 'platform'::name, 'text'::name);
SELECT col_type_is('public'::name, 'device_tokens'::name, 'token'::name, 'text'::name);
SELECT col_type_is('public'::name, 'device_tokens'::name, 'locale'::name, 'text'::name);
SELECT col_type_is('public'::name, 'device_tokens'::name, 'settings'::name, 'jsonb'::name);
SELECT col_type_is('public'::name, 'device_tokens'::name, 'created_at'::name, 'timestamp with time zone'::name);
SELECT col_type_is('public'::name, 'device_tokens'::name, 'last_seen_at'::name, 'timestamp with time zone'::name);

SELECT has_pk('public'::name, 'device_tokens'::name);
SELECT col_is_pk('public'::name, 'device_tokens'::name, 'token'::name);

SELECT col_not_null('public'::name, 'device_tokens'::name, 'profile_id'::name);
SELECT col_not_null('public'::name, 'device_tokens'::name, 'platform'::name);
SELECT col_not_null('public'::name, 'device_tokens'::name, 'token'::name);
SELECT col_not_null('public'::name, 'device_tokens'::name, 'locale'::name);
SELECT col_not_null('public'::name, 'device_tokens'::name, 'settings'::name);
SELECT col_not_null('public'::name, 'device_tokens'::name, 'created_at'::name);
SELECT col_not_null('public'::name, 'device_tokens'::name, 'last_seen_at'::name);

SELECT col_default_is('public', 'device_tokens', 'locale', 'en', 'locale default is en');
SELECT col_default_is('public', 'device_tokens', 'settings', '{}'::jsonb, 'settings default is empty jsonb');
SELECT col_default_is('public', 'device_tokens', 'created_at', 'now()', 'created_at default is now()');
SELECT col_default_is('public', 'device_tokens', 'last_seen_at', 'now()', 'last_seen_at default is now()');

SELECT fk_ok('public', 'device_tokens', 'profile_id', 'public', 'profiles', 'id');

SELECT col_type_is('public'::name, 'device_tokens'::name, 'utc_offset_minutes'::name, 'smallint'::name);

SELECT has_index('public'::name, 'device_tokens'::name, 'device_tokens_profile_idx'::name, ARRAY ['profile_id']::name[]);
SELECT has_check('public'::name, 'device_tokens'::name, 'device_tokens has its checks');

SELECT * FROM finish();

ROLLBACK;
