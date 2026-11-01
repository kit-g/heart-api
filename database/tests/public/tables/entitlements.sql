BEGIN;

SELECT plan(8);

SELECT has_table('public'::name, 'entitlements'::name);
SELECT columns_are('public', 'entitlements', ARRAY ['user_id', 'entitlement', 'granted_at']);
SELECT col_is_pk('public'::name, 'entitlements'::name, ARRAY ['user_id', 'entitlement'], 'one row per account and entitlement');
SELECT col_not_null('public'::name, 'entitlements'::name, 'granted_at'::name);
SELECT col_default_is('public', 'entitlements', 'granted_at', 'now()', 'granted_at defaults to now');
SELECT fk_ok('public', 'entitlements', 'user_id', 'public', 'profiles', 'id');

DO
$$
BEGIN
    PERFORM create_test_profile('entitled');
END
$$;

SELECT lives_ok($$ INSERT INTO entitlements (user_id, entitlement) VALUES ('entitled', 'coach') $$, 'a snake_case name');
SELECT throws_ok(
               $$ INSERT INTO entitlements (user_id, entitlement) VALUES ('entitled', 'Not A Name') $$,
               '23514',
               NULL,
               'anything else is refused'
       );

SELECT * FROM finish();

ROLLBACK;
