BEGIN;

SELECT plan(22);

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

SELECT has_index('public'::name, 'template_exercise_sets'::name, 'template_exercise_sets_template_exercise_id_idx'::name);

-- fixtures for the CHECK-constraint assertions below
DO
$$
BEGIN
    PERFORM create_test_template_exercise(
            create_test_template(_user_id := create_test_profile('tes-check-user'), _name := 'tes check template'),
            create_test_exercise('TES Check Bench', _user_id := 'tes-check-user')
            );
END
$$;

SELECT lives_ok(
               $$
               INSERT INTO template_exercise_sets (template_exercise_id, set_order, weight, reps, duration, distance)
               VALUES (
                   (SELECT te.id FROM template_exercises te JOIN templates t ON t.id = te.template_id WHERE t.name = 'tes check template'),
                   0, 0, 0, 0, 0
               )
               $$,
               'zero measurements are allowed'
       );

SELECT throws_ok(
               $$
               INSERT INTO template_exercise_sets (template_exercise_id, set_order, weight)
               VALUES (
                   (SELECT te.id FROM template_exercises te JOIN templates t ON t.id = te.template_id WHERE t.name = 'tes check template'),
                   1, -50
               )
               $$,
               '23514',
               NULL,
               'a negative weight is rejected'
       );

SELECT throws_ok(
               $$
               INSERT INTO template_exercise_sets (template_exercise_id, set_order, reps)
               VALUES (
                   (SELECT te.id FROM template_exercises te JOIN templates t ON t.id = te.template_id WHERE t.name = 'tes check template'),
                   1, -5
               )
               $$,
               '23514',
               NULL,
               'negative reps are rejected'
       );

SELECT throws_ok(
               $$
               INSERT INTO template_exercise_sets (template_exercise_id, set_order, duration)
               VALUES (
                   (SELECT te.id FROM template_exercises te JOIN templates t ON t.id = te.template_id WHERE t.name = 'tes check template'),
                   1, -30
               )
               $$,
               '23514',
               NULL,
               'a negative duration is rejected'
       );

SELECT throws_ok(
               $$
               INSERT INTO template_exercise_sets (template_exercise_id, set_order, distance)
               VALUES (
                   (SELECT te.id FROM template_exercises te JOIN templates t ON t.id = te.template_id WHERE t.name = 'tes check template'),
                   1, -1.5
               )
               $$,
               '23514',
               NULL,
               'a negative distance is rejected'
       );

SELECT * FROM finish();

ROLLBACK;
