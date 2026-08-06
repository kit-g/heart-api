BEGIN;

SELECT plan(16);

SELECT has_table('public'::name, 'template_exercises'::name);

SELECT columns_are(
               'public',
               'template_exercises',
               ARRAY [
                   'id',
                   'template_id',
                   'exercise_id',
                   'exercise_order'
                   ]
       );

SELECT col_type_is('public'::name, 'template_exercises'::name, 'id'::name, 'uuid'::name);
SELECT col_type_is('public'::name, 'template_exercises'::name, 'template_id'::name, 'uuid'::name);
SELECT col_type_is('public'::name, 'template_exercises'::name, 'exercise_id'::name, 'uuid'::name);
SELECT col_type_is('public'::name, 'template_exercises'::name, 'exercise_order'::name, 'integer'::name);

SELECT has_pk('public'::name, 'template_exercises'::name, 'template_exercises has a primary key');
SELECT col_is_pk('public'::name, 'template_exercises'::name, 'id'::name, 'id is the primary key');

SELECT col_not_null('public'::name, 'template_exercises'::name, 'id'::name);
SELECT col_not_null('public'::name, 'template_exercises'::name, 'template_id'::name);
SELECT col_not_null('public'::name, 'template_exercises'::name, 'exercise_id'::name);
SELECT col_not_null('public'::name, 'template_exercises'::name, 'exercise_order'::name);

SELECT col_default_is('public', 'template_exercises', 'id', 'uuidv7()', 'id default is uuidv7()');

SELECT fk_ok('public', 'template_exercises', 'template_id', 'public', 'templates', 'id');
SELECT fk_ok('public', 'template_exercises', 'exercise_id', 'public', 'exercises', 'id');

SELECT has_index('public'::name, 'template_exercises'::name, 'template_exercises_template_id_idx'::name);

SELECT * FROM finish();

ROLLBACK;
