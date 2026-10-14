BEGIN;

SELECT plan(24);

SELECT has_table('public'::name, 'program_bases'::name);

SELECT columns_are(
               'public',
               'program_bases',
               ARRAY ['id', 'user_id', 'program_id', 'exercise_id', 'value', 'workout_id', 'action_id', 'at', 'created_at']
       );

SELECT col_type_is('public'::name, 'program_bases'::name, 'id'::name, 'uuid'::name);
SELECT col_type_is('public'::name, 'program_bases'::name, 'user_id'::name, 'text'::name);
SELECT col_type_is('public'::name, 'program_bases'::name, 'program_id'::name, 'uuid'::name);
SELECT col_type_is('public'::name, 'program_bases'::name, 'exercise_id'::name, 'uuid'::name);
SELECT col_type_is('public'::name, 'program_bases'::name, 'value'::name, 'real'::name);
SELECT col_type_is('public'::name, 'program_bases'::name, 'workout_id'::name, 'uuid'::name);
SELECT col_type_is('public'::name, 'program_bases'::name, 'action_id'::name, 'uuid'::name);
SELECT col_type_is('public'::name, 'program_bases'::name, 'at'::name, 'timestamp with time zone'::name);
SELECT col_type_is('public'::name, 'program_bases'::name, 'created_at'::name, 'timestamp with time zone'::name);

SELECT col_is_pk('public'::name, 'program_bases'::name, 'id'::name, 'id is the primary key');
SELECT col_not_null('public'::name, 'program_bases'::name, 'user_id'::name);
SELECT col_not_null('public'::name, 'program_bases'::name, 'program_id'::name);
SELECT col_not_null('public'::name, 'program_bases'::name, 'exercise_id'::name);
SELECT col_not_null('public'::name, 'program_bases'::name, 'value'::name);
SELECT col_not_null('public'::name, 'program_bases'::name, 'at'::name);

SELECT fk_ok(
               'public', 'program_bases', ARRAY ['program_id', 'user_id'],
               'public', 'programs', ARRAY ['id', 'user_id']
       );
SELECT fk_ok(
               'public', 'program_bases', ARRAY ['action_id', 'user_id'],
               'public', 'program_actions', ARRAY ['id', 'user_id']
       );
SELECT fk_ok('public', 'program_bases', 'exercise_id', 'public', 'exercises', 'id');
SELECT fk_ok('public', 'program_bases', 'workout_id', 'public', 'workouts', 'id');

SELECT has_index('public'::name, 'program_bases'::name, 'program_bases_program_idx'::name);
SELECT index_is_unique('public'::name, 'program_bases'::name, 'program_bases_workout_idx'::name);

SELECT throws_ok(
               $$
               WITH _p AS (
                   INSERT INTO programs (user_id, name) VALUES (create_test_profile(), 'p') RETURNING user_id, id
               )
               INSERT INTO program_bases (user_id, program_id, exercise_id, value, at)
               SELECT p.user_id, p.id, create_test_exercise(), 0, now() FROM _p p
               $$,
               '23514', NULL, 'a base is above zero'
       );

SELECT * FROM finish();

ROLLBACK;
