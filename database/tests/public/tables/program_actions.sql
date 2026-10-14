BEGIN;

SELECT plan(20);

SELECT has_table('public'::name, 'program_actions'::name);

SELECT columns_are(
               'public',
               'program_actions',
               ARRAY ['id', 'user_id', 'program_id', 'kind', 'week', 'at', 'created_at']
       );

SELECT col_type_is('public'::name, 'program_actions'::name, 'id'::name, 'uuid'::name);
SELECT col_type_is('public'::name, 'program_actions'::name, 'user_id'::name, 'text'::name);
SELECT col_type_is('public'::name, 'program_actions'::name, 'program_id'::name, 'uuid'::name);
SELECT col_type_is('public'::name, 'program_actions'::name, 'kind'::name, 'text'::name);
SELECT col_type_is('public'::name, 'program_actions'::name, 'week'::name, 'smallint'::name);
SELECT col_type_is('public'::name, 'program_actions'::name, 'at'::name, 'timestamp with time zone'::name);
SELECT col_type_is('public'::name, 'program_actions'::name, 'created_at'::name, 'timestamp with time zone'::name);

SELECT col_is_pk('public'::name, 'program_actions'::name, 'id'::name, 'id is the primary key');
SELECT col_not_null('public'::name, 'program_actions'::name, 'user_id'::name);
SELECT col_not_null('public'::name, 'program_actions'::name, 'program_id'::name);
SELECT col_not_null('public'::name, 'program_actions'::name, 'kind'::name);
SELECT col_not_null('public'::name, 'program_actions'::name, 'at'::name);
SELECT col_default_is('public', 'program_actions', 'id', 'uuidv7()', 'id default is uuidv7()');

-- composite so an action can only belong to a program of the same user
SELECT fk_ok(
               'public', 'program_actions', ARRAY ['program_id', 'user_id'],
               'public', 'programs', ARRAY ['id', 'user_id']
       );
SELECT has_index('public'::name, 'program_actions'::name, 'program_actions_program_idx'::name);

SELECT throws_ok(
               $$
               WITH _p AS (
                   INSERT INTO programs (user_id, name) VALUES (create_test_profile(), 'p') RETURNING user_id, id
               )
               INSERT INTO program_actions (user_id, program_id, kind, at)
               SELECT user_id, id, 'replay', now() FROM _p
               $$,
               '23514', NULL, 'a replay names a week'
       );
SELECT throws_ok(
               $$
               WITH _p AS (
                   INSERT INTO programs (user_id, name) VALUES (create_test_profile(), 'p') RETURNING user_id, id
               )
               INSERT INTO program_actions (user_id, program_id, kind, week, at)
               SELECT user_id, id, 'pause', 2, now() FROM _p
               $$,
               '23514', NULL, 'only a replay names a week'
       );
SELECT throws_ok(
               $$
               WITH _p AS (
                   INSERT INTO programs (user_id, name) VALUES (create_test_profile(), 'p') RETURNING user_id, id
               )
               INSERT INTO program_actions (user_id, program_id, kind, at)
               SELECT user_id, id, 'deload', now() FROM _p
               $$,
               '23514', NULL, 'the kinds are a closed list'
       );

SELECT * FROM finish();

ROLLBACK;
