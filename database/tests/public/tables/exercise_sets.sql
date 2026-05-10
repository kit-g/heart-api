BEGIN;

SELECT plan(21);

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
                   'set_order'
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

SELECT has_pk('public'::name, 'exercise_sets'::name, 'exercise_sets has a primary key');
SELECT col_is_pk('public'::name, 'exercise_sets'::name, 'id'::name, 'id is the primary key');

SELECT col_not_null('public'::name, 'exercise_sets'::name, 'id'::name);
SELECT col_not_null('public'::name, 'exercise_sets'::name, 'workout_exercise_id'::name);
SELECT col_not_null('public'::name, 'exercise_sets'::name, 'set_order'::name);
SELECT col_not_null('public'::name, 'exercise_sets'::name, 'completed'::name);

SELECT col_default_is('public', 'exercise_sets', 'id', 'uuidv7()', 'id default is uuidv7()');
SELECT col_default_is('public', 'exercise_sets', 'completed', 'false', 'completed default is false');

SELECT fk_ok('public', 'exercise_sets', 'workout_exercise_id', 'public', 'workout_exercises', 'id');

SELECT * FROM finish();

ROLLBACK;
