BEGIN;

SELECT plan(16);

SELECT has_table('public'::name, 'workout_exercises'::name);

SELECT columns_are(
               'public',
               'workout_exercises',
               ARRAY [
                   'id',
                   'workout_id',
                   'exercise_id',
                   'exercise_order'
                   ]
       );

SELECT col_type_is('public'::name, 'workout_exercises'::name, 'id'::name, 'uuid'::name);
SELECT col_type_is('public'::name, 'workout_exercises'::name, 'workout_id'::name, 'uuid'::name);
SELECT col_type_is('public'::name, 'workout_exercises'::name, 'exercise_id'::name, 'uuid'::name);
SELECT col_type_is('public'::name, 'workout_exercises'::name, 'exercise_order'::name, 'integer'::name);

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

SELECT * FROM finish();

ROLLBACK;
