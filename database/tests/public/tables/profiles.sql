BEGIN;

SELECT plan(19);

SELECT has_table('public'::name, 'profiles'::name);

SELECT columns_are(
               'public',
               'profiles',
               ARRAY [
                   'id',
                   'username',
                   'email',
                   'avatar_url',
                   'account_deletion_schedule',
                   'scheduled_for_deletion_at',
                   'updated_at',
                   'settings',
                   'apple_refresh_token',
                   'apple_client_id'
                   ]
       );

SELECT col_type_is('public'::name, 'profiles'::name, 'id'::name, 'text'::name);
SELECT col_type_is('public'::name, 'profiles'::name, 'username'::name, 'text'::name);
SELECT col_type_is('public'::name, 'profiles'::name, 'email'::name, 'text'::name);
SELECT col_type_is('public'::name, 'profiles'::name, 'avatar_url'::name, 'text'::name);
SELECT col_type_is('public'::name, 'profiles'::name, 'account_deletion_schedule'::name, 'text'::name);
SELECT col_type_is('public'::name, 'profiles'::name, 'scheduled_for_deletion_at'::name, 'timestamp with time zone'::name);
SELECT col_type_is('public'::name, 'profiles'::name, 'updated_at'::name, 'timestamp with time zone'::name);
SELECT col_type_is('public'::name, 'profiles'::name, 'settings'::name, 'jsonb'::name);
SELECT col_type_is('public'::name, 'profiles'::name, 'apple_refresh_token'::name, 'text'::name);
SELECT col_type_is('public'::name, 'profiles'::name, 'apple_client_id'::name, 'text'::name);

SELECT has_pk('public'::name, 'profiles'::name, 'profiles has a primary key');
SELECT col_is_pk('public'::name, 'profiles'::name, 'id'::name, 'id is the primary key');

SELECT col_not_null('public'::name, 'profiles'::name, 'id'::name);
SELECT col_not_null('public'::name, 'profiles'::name, 'updated_at'::name);
SELECT col_not_null('public'::name, 'profiles'::name, 'settings'::name);

SELECT col_default_is('public', 'profiles', 'updated_at', 'now()', 'updated_at default is now()');
SELECT col_default_is('public', 'profiles', 'settings', '{}', 'settings default is empty jsonb');

SELECT * FROM finish();

ROLLBACK;
