BEGIN;

SELECT plan(21);

SELECT has_table('public'::name, 'skips'::name);

SELECT columns_are(
               'public',
               'skips',
               ARRAY ['id', 'user_id', 'at', 'reason', 'weather', 'template_id', 'program_id', 'created_at']
       );

SELECT col_type_is('public'::name, 'skips'::name, 'id'::name, 'uuid'::name);
SELECT col_type_is('public'::name, 'skips'::name, 'user_id'::name, 'text'::name);
SELECT col_type_is('public'::name, 'skips'::name, 'at'::name, 'timestamp with time zone'::name);
SELECT col_type_is('public'::name, 'skips'::name, 'reason'::name, 'text'::name);
SELECT col_type_is('public'::name, 'skips'::name, 'weather'::name, 'jsonb'::name);
SELECT col_type_is('public'::name, 'skips'::name, 'template_id'::name, 'uuid'::name);
SELECT col_type_is('public'::name, 'skips'::name, 'program_id'::name, 'uuid'::name);
SELECT col_type_is('public'::name, 'skips'::name, 'created_at'::name, 'timestamp with time zone'::name);

SELECT col_is_pk('public'::name, 'skips'::name, 'id'::name, 'id is the primary key');
SELECT col_not_null('public'::name, 'skips'::name, 'user_id'::name);
SELECT col_not_null('public'::name, 'skips'::name, 'at'::name);
SELECT col_default_is('public', 'skips', 'id', 'uuidv7()', 'id default is uuidv7()');

SELECT fk_ok('public', 'skips', 'user_id', 'public', 'profiles', 'id');
SELECT fk_ok('public', 'skips', 'template_id', 'public', 'templates', 'id');
SELECT fk_ok('public', 'skips', 'program_id', 'public', 'programs', 'id');

SELECT has_index('public'::name, 'skips'::name, 'skips_user_id_idx'::name);
SELECT has_index('public'::name, 'skips'::name, 'skips_program_id_idx'::name);

SELECT throws_ok(
               $$INSERT INTO skips (user_id, at, reason) VALUES (create_test_profile(), now(), 'Just No')$$,
               '23514', NULL, 'a reason is a snake_case tag'
       );
SELECT throws_ok(
               $$INSERT INTO skips (user_id, at, weather) VALUES (create_test_profile(), now(), '[]')$$,
               '23514', NULL, 'the weather is an object'
       );

SELECT * FROM finish();

ROLLBACK;
