BEGIN;

SELECT plan(37);

SELECT has_table('public'::name, 'exercise_sets'::name);

SELECT columns_are(
               'public',
               'exercise_sets',
               ARRAY [
                   'id',
                   'workout_exercise_id',
                   'weight',
                   'reps',
                   'duration',
                   'distance',
                   'completed',
                   'started_at',
                   'completed_at',
                   'set_order',
                   'set_type',
                   'rpe'
                   ]
       );

SELECT col_type_is('public'::name, 'exercise_sets'::name, 'id'::name, 'uuid'::name);
SELECT col_type_is('public'::name, 'exercise_sets'::name, 'workout_exercise_id'::name, 'uuid'::name);
SELECT col_type_is('public'::name, 'exercise_sets'::name, 'weight'::name, 'real'::name);
SELECT col_type_is('public'::name, 'exercise_sets'::name, 'reps'::name, 'integer'::name);
SELECT col_type_is('public'::name, 'exercise_sets'::name, 'duration'::name, 'integer'::name);
SELECT col_type_is('public'::name, 'exercise_sets'::name, 'distance'::name, 'real'::name);
SELECT col_type_is('public'::name, 'exercise_sets'::name, 'completed'::name, 'boolean'::name);
SELECT col_type_is('public'::name, 'exercise_sets'::name, 'started_at'::name, 'timestamp with time zone'::name);
SELECT col_type_is('public'::name, 'exercise_sets'::name, 'completed_at'::name, 'timestamp with time zone'::name);
SELECT col_type_is('public'::name, 'exercise_sets'::name, 'set_order'::name, 'integer'::name);
SELECT col_type_is('public'::name, 'exercise_sets'::name, 'set_type'::name, 'character(1)'::name);
SELECT col_type_is('public'::name, 'exercise_sets'::name, 'rpe'::name, 'real'::name);

SELECT has_pk('public'::name, 'exercise_sets'::name, 'exercise_sets has a primary key');
SELECT col_is_pk('public'::name, 'exercise_sets'::name, 'id'::name, 'id is the primary key');

SELECT col_not_null('public'::name, 'exercise_sets'::name, 'id'::name);
SELECT col_not_null('public'::name, 'exercise_sets'::name, 'workout_exercise_id'::name);
SELECT col_not_null('public'::name, 'exercise_sets'::name, 'set_order'::name);
SELECT col_not_null('public'::name, 'exercise_sets'::name, 'completed'::name);

SELECT col_default_is('public', 'exercise_sets', 'id', 'uuidv7()', 'id default is uuidv7()');
SELECT col_default_is('public', 'exercise_sets', 'completed', 'false', 'completed default is false');

SELECT fk_ok('public', 'exercise_sets', 'workout_exercise_id', 'public', 'workout_exercises', 'id');

SELECT has_index('public'::name, 'exercise_sets'::name, 'exercise_sets_workout_exercise_id_idx'::name);

-- fixtures for the CHECK-constraint assertions below
DO
$$
BEGIN
    PERFORM create_test_workout_exercise(
            create_test_workout(_user_id := create_test_profile('es-check-user'), _name := 'es check workout'),
            create_test_exercise('ES Check Bench', _user_id := 'es-check-user')
            );
END
$$;

SELECT lives_ok(
               $$
               INSERT INTO exercise_sets (workout_exercise_id, set_order, weight, reps, duration, distance)
               VALUES (
                   (SELECT we.id FROM workout_exercises we JOIN workouts w ON w.id = we.workout_id WHERE w.name = 'es check workout'),
                   0, 0, 0, 0, 0
               )
               $$,
               'zero measurements are allowed'
       );

SELECT throws_ok(
               $$
               INSERT INTO exercise_sets (workout_exercise_id, set_order, weight)
               VALUES (
                   (SELECT we.id FROM workout_exercises we JOIN workouts w ON w.id = we.workout_id WHERE w.name = 'es check workout'),
                   1, -50
               )
               $$,
               '23514',
               NULL,
               'a negative weight is rejected'
       );

SELECT throws_ok(
               $$
               INSERT INTO exercise_sets (workout_exercise_id, set_order, reps)
               VALUES (
                   (SELECT we.id FROM workout_exercises we JOIN workouts w ON w.id = we.workout_id WHERE w.name = 'es check workout'),
                   1, -5
               )
               $$,
               '23514',
               NULL,
               'negative reps are rejected'
       );

SELECT throws_ok(
               $$
               INSERT INTO exercise_sets (workout_exercise_id, set_order, duration)
               VALUES (
                   (SELECT we.id FROM workout_exercises we JOIN workouts w ON w.id = we.workout_id WHERE w.name = 'es check workout'),
                   1, -30
               )
               $$,
               '23514',
               NULL,
               'a negative duration is rejected'
       );

SELECT throws_ok(
               $$
               INSERT INTO exercise_sets (workout_exercise_id, set_order, distance)
               VALUES (
                   (SELECT we.id FROM workout_exercises we JOIN workouts w ON w.id = we.workout_id WHERE w.name = 'es check workout'),
                   1, -1.5
               )
               $$,
               '23514',
               NULL,
               'a negative distance is rejected'
       );

SELECT lives_ok(
               $$
               INSERT INTO exercise_sets (workout_exercise_id, set_order, set_type, rpe)
               VALUES (
                   (SELECT we.id FROM workout_exercises we JOIN workouts w ON w.id = we.workout_id WHERE w.name = 'es check workout'),
                   1, 'w', 6.5
               )
               $$,
               'a warm-up rated in a half step is allowed'
       );

SELECT lives_ok(
               $$
               INSERT INTO exercise_sets (workout_exercise_id, set_order, rpe)
               VALUES (
                   (SELECT we.id FROM workout_exercises we JOIN workouts w ON w.id = we.workout_id WHERE w.name = 'es check workout'),
                   1, 1
               )
               $$,
               'the bottom of the RPE scale is allowed'
       );

SELECT lives_ok(
               $$
               INSERT INTO exercise_sets (workout_exercise_id, set_order, rpe)
               VALUES (
                   (SELECT we.id FROM workout_exercises we JOIN workouts w ON w.id = we.workout_id WHERE w.name = 'es check workout'),
                   1, 10
               )
               $$,
               'the top of the RPE scale is allowed'
       );

SELECT throws_ok(
               $$
               INSERT INTO exercise_sets (workout_exercise_id, set_order, rpe)
               VALUES (
                   (SELECT we.id FROM workout_exercises we JOIN workouts w ON w.id = we.workout_id WHERE w.name = 'es check workout'),
                   1, 8.3
               )
               $$,
               '23514',
               NULL,
               'an RPE between half steps is rejected'
       );

SELECT throws_ok(
               $$
               INSERT INTO exercise_sets (workout_exercise_id, set_order, rpe)
               VALUES (
                   (SELECT we.id FROM workout_exercises we JOIN workouts w ON w.id = we.workout_id WHERE w.name = 'es check workout'),
                   1, 11
               )
               $$,
               '23514',
               NULL,
               'an RPE above 10 is rejected'
       );

SELECT throws_ok(
               $$
               INSERT INTO exercise_sets (workout_exercise_id, set_order, rpe)
               VALUES (
                   (SELECT we.id FROM workout_exercises we JOIN workouts w ON w.id = we.workout_id WHERE w.name = 'es check workout'),
                   1, 0.5
               )
               $$,
               '23514',
               NULL,
               'an RPE below 1 is rejected'
       );

SELECT throws_ok(
               $$
               INSERT INTO exercise_sets (workout_exercise_id, set_order, set_type)
               VALUES (
                   (SELECT we.id FROM workout_exercises we JOIN workouts w ON w.id = we.workout_id WHERE w.name = 'es check workout'),
                   1, 'x'
               )
               $$,
               '23514',
               NULL,
               'an unknown set type letter is rejected'
       );

SELECT throws_ok(
               $$
               INSERT INTO exercise_sets (workout_exercise_id, set_order, set_type)
               VALUES (
                   (SELECT we.id FROM workout_exercises we JOIN workouts w ON w.id = we.workout_id WHERE w.name = 'es check workout'),
                   1, 'warmup'
               )
               $$,
               '22001',
               NULL,
               'a word is too long for the one-letter column, never silently cut'
       );

SELECT * FROM finish();

ROLLBACK;
