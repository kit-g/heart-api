BEGIN;

SELECT plan(19);

SELECT has_table('public'::name, 'workout_exercises'::name);

SELECT columns_are(
               'public',
               'workout_exercises',
               ARRAY [
                   'id',
                   'workout_id',
                   'exercise_id',
                   'exercise_order',
                   'met'
                   ]
       );

SELECT col_type_is('public'::name, 'workout_exercises'::name, 'id'::name, 'uuid'::name);
SELECT col_type_is('public'::name, 'workout_exercises'::name, 'workout_id'::name, 'uuid'::name);
SELECT col_type_is('public'::name, 'workout_exercises'::name, 'exercise_id'::name, 'uuid'::name);
SELECT col_type_is('public'::name, 'workout_exercises'::name, 'exercise_order'::name, 'integer'::name);
SELECT col_type_is('public'::name, 'workout_exercises'::name, 'met'::name, 'real'::name);

SELECT has_pk('public'::name, 'workout_exercises'::name, 'workout_exercises has a primary key');
SELECT col_is_pk('public'::name, 'workout_exercises'::name, 'id'::name, 'id is the primary key');

SELECT col_not_null('public'::name, 'workout_exercises'::name, 'id'::name);
SELECT col_not_null('public'::name, 'workout_exercises'::name, 'workout_id'::name);
SELECT col_not_null('public'::name, 'workout_exercises'::name, 'exercise_id'::name);
SELECT col_not_null('public'::name, 'workout_exercises'::name, 'exercise_order'::name);

SELECT col_default_is('public', 'workout_exercises', 'id', 'uuidv7()', 'id default is uuidv7()');

SELECT fk_ok('public', 'workout_exercises', 'workout_id', 'public', 'workouts', 'id');
SELECT fk_ok('public', 'workout_exercises', 'exercise_id', 'public', 'exercises', 'id');

SELECT has_index('public'::name, 'workout_exercises'::name, 'workout_exercises_workout_id_idx'::name);

-- fixtures for the CHECK-constraint assertions below
DO
$$
BEGIN
    PERFORM create_test_workout(_user_id := create_test_profile('we-check-user'), _name := 'we check workout');
    PERFORM create_test_exercise('WE Check Bench', _user_id := 'we-check-user');
END
$$;

SELECT lives_ok(
               $$
               INSERT INTO workout_exercises (workout_id, exercise_id, exercise_order, met)
               VALUES (
                   (SELECT id FROM workouts WHERE name = 'we check workout'),
                   (SELECT id FROM exercises WHERE name = 'WE Check Bench'),
                   0, 0
               )
               $$,
               'a zero met is allowed'
       );

SELECT throws_ok(
               $$
               INSERT INTO workout_exercises (workout_id, exercise_id, exercise_order, met)
               VALUES (
                   (SELECT id FROM workouts WHERE name = 'we check workout'),
                   (SELECT id FROM exercises WHERE name = 'WE Check Bench'),
                   1, -3.5
               )
               $$,
               '23514',
               NULL,
               'a negative met is rejected'
       );

SELECT * FROM finish();

ROLLBACK;
