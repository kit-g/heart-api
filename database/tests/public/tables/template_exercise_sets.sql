BEGIN;

SELECT plan(16);

SELECT has_table('public'::name, 'template_exercise_sets'::name);

SELECT columns_are(
               'public',
               'template_exercise_sets',
               ARRAY [
                   'id',
                   'template_exercise_id',
                   'weight',
                   'reps',
                   'duration',
                   'distance',
                   'set_order'
                   ]
       );

SELECT col_type_is('public'::name, 'template_exercise_sets'::name, 'id'::name, 'uuid'::name);
SELECT col_type_is('public'::name, 'template_exercise_sets'::name, 'template_exercise_id'::name, 'uuid'::name);
SELECT col_type_is('public'::name, 'template_exercise_sets'::name, 'weight'::name, 'real'::name);
SELECT col_type_is('public'::name, 'template_exercise_sets'::name, 'reps'::name, 'integer'::name);
SELECT col_type_is('public'::name, 'template_exercise_sets'::name, 'duration'::name, 'integer'::name);
SELECT col_type_is('public'::name, 'template_exercise_sets'::name, 'distance'::name, 'real'::name);
SELECT col_type_is('public'::name, 'template_exercise_sets'::name, 'set_order'::name, 'integer'::name);

SELECT has_pk('public'::name, 'template_exercise_sets'::name, 'template_exercise_sets has a primary key');
SELECT col_is_pk('public'::name, 'template_exercise_sets'::name, 'id'::name, 'id is the primary key');

SELECT col_not_null('public'::name, 'template_exercise_sets'::name, 'id'::name);
SELECT col_not_null('public'::name, 'template_exercise_sets'::name, 'template_exercise_id'::name);
SELECT col_not_null('public'::name, 'template_exercise_sets'::name, 'set_order'::name);

SELECT col_default_is('public', 'template_exercise_sets', 'id', 'uuidv7()', 'id default is uuidv7()');

SELECT fk_ok('public', 'template_exercise_sets', 'template_exercise_id', 'public', 'template_exercises', 'id');

SELECT * FROM finish();

ROLLBACK;
