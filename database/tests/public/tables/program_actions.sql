BEGIN;

SELECT plan(31);

SELECT has_table('public'::name, 'program_actions'::name);

SELECT columns_are(
               'public',
               'program_actions',
               ARRAY ['id', 'user_id', 'program_id', 'kind', 'week', 'at', 'created_at', 'from_exercise', 'to_exercise', 'workout_id', 'exercise_id', 'slot', 'stage']
       );

SELECT col_type_is('public'::name, 'program_actions'::name, 'id'::name, 'uuid'::name);
SELECT col_type_is('public'::name, 'program_actions'::name, 'user_id'::name, 'text'::name);
SELECT col_type_is('public'::name, 'program_actions'::name, 'program_id'::name, 'uuid'::name);
SELECT col_type_is('public'::name, 'program_actions'::name, 'kind'::name, 'text'::name);
SELECT col_type_is('public'::name, 'program_actions'::name, 'week'::name, 'smallint'::name);
SELECT col_type_is('public'::name, 'program_actions'::name, 'at'::name, 'timestamp with time zone'::name);
SELECT col_type_is('public'::name, 'program_actions'::name, 'created_at'::name, 'timestamp with time zone'::name);
SELECT col_type_is('public'::name, 'program_actions'::name, 'exercise_id'::name, 'uuid'::name);
SELECT col_type_is('public'::name, 'program_actions'::name, 'slot'::name, 'uuid'::name);
SELECT col_type_is('public'::name, 'program_actions'::name, 'stage'::name, 'smallint'::name);

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

SELECT lives_ok(
               $$
               WITH _p AS (
                   INSERT INTO programs (user_id, name) VALUES (create_test_profile(), 'p') RETURNING user_id, id
               )
               INSERT INTO program_actions (user_id, program_id, kind, at)
               SELECT user_id, id, 'lighter', now() FROM _p
               $$,
               'a lighter week is an action'
       );

SELECT fk_ok('public', 'program_actions', 'workout_id', 'public', 'workouts', 'id');
SELECT throws_ok(
               $$
               WITH _p AS (
                   INSERT INTO programs (user_id, name) VALUES (create_test_profile(), 'p') RETURNING user_id, id
               )
               INSERT INTO program_actions (user_id, program_id, kind, at)
               SELECT user_id, id, 'advance', now() FROM _p
               $$,
               '23514', NULL, 'an advance names its exercises'
       );
SELECT throws_ok(
               $$
               WITH _p AS (
                   INSERT INTO programs (user_id, name) VALUES (create_test_profile(), 'p') RETURNING user_id, id
               )
               INSERT INTO program_actions (user_id, program_id, kind, from_exercise, to_exercise, at)
               SELECT user_id, id, 'pause', gen_random_uuid(), gen_random_uuid(), now() FROM _p
               $$,
               '23514', NULL, 'only an advance names exercises'
       );

SELECT throws_ok(
               $$
               WITH _p AS (
                   INSERT INTO programs (user_id, name) VALUES (create_test_profile(), 'p') RETURNING user_id, id
               )
               INSERT INTO program_actions (user_id, program_id, kind, exercise_id, at)
               SELECT user_id, id, 'stage', gen_random_uuid(), now() FROM _p
               $$,
               '23514', NULL, 'a stage names the stage it moved to'
       );
SELECT throws_ok(
               $$
               WITH _p AS (
                   INSERT INTO programs (user_id, name) VALUES (create_test_profile(), 'p') RETURNING user_id, id
               )
               INSERT INTO program_actions (user_id, program_id, kind, exercise_id, stage, at)
               SELECT user_id, id, 'stage', gen_random_uuid(), 20, now() FROM _p
               $$,
               '23514', NULL, 'twenty stages at most, so the last is 19'
       );
SELECT throws_ok(
               $$
               WITH _p AS (
                   INSERT INTO programs (user_id, name) VALUES (create_test_profile(), 'p') RETURNING user_id, id
               )
               INSERT INTO program_actions (user_id, program_id, kind, slot, at)
               SELECT user_id, id, 'lighter', gen_random_uuid(), now() FROM _p
               $$,
               '23514', NULL, 'only a stage names a slot'
       );
SELECT lives_ok(
               $$
               WITH _p AS (
                   INSERT INTO programs (user_id, name) VALUES (create_test_profile(), 'p') RETURNING user_id, id
               )
               INSERT INTO program_actions (user_id, program_id, kind, exercise_id, slot, stage, at)
               SELECT user_id, id, 'stage', gen_random_uuid(), gen_random_uuid(), 2, now() FROM _p
               $$,
               'a stage names its exercise, slot and stage'
       );

SELECT * FROM finish();

ROLLBACK;
