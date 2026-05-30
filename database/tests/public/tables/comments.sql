BEGIN;

SELECT plan(21);

SELECT has_table('public'::name, 'comments'::name);

SELECT columns_are(
               'public',
               'comments',
               ARRAY [
                   'id',
                   'author_id',
                   'body',
                   'workout_id',
                   'workout_exercise_id',
                   'exercise_set_id',
                   'workout_image_id',
                   'created_at',
                   'edited_at'
                   ]
       );

SELECT col_type_is('public'::name, 'comments'::name, 'id'::name, 'uuid'::name);
SELECT col_type_is('public'::name, 'comments'::name, 'author_id'::name, 'text'::name);
SELECT col_type_is('public'::name, 'comments'::name, 'body'::name, 'text'::name);
SELECT col_type_is('public'::name, 'comments'::name, 'workout_id'::name, 'uuid'::name);
SELECT col_type_is('public'::name, 'comments'::name, 'workout_exercise_id'::name, 'uuid'::name);
SELECT col_type_is('public'::name, 'comments'::name, 'exercise_set_id'::name, 'uuid'::name);
SELECT col_type_is('public'::name, 'comments'::name, 'workout_image_id'::name, 'uuid'::name);

SELECT has_pk('public'::name, 'comments'::name);
SELECT col_is_pk('public'::name, 'comments'::name, 'id'::name);

SELECT col_not_null('public'::name, 'comments'::name, 'id'::name);
SELECT col_not_null('public'::name, 'comments'::name, 'author_id'::name);
SELECT col_not_null('public'::name, 'comments'::name, 'body'::name);
SELECT col_not_null('public'::name, 'comments'::name, 'created_at'::name);

SELECT col_default_is('public', 'comments', 'id', 'uuidv7()', 'id default is uuidv7()');

SELECT fk_ok('public', 'comments', 'author_id', 'public', 'profiles', 'id');
SELECT fk_ok('public', 'comments', 'workout_id', 'public', 'workouts', 'id');
SELECT fk_ok('public', 'comments', 'workout_exercise_id', 'public', 'workout_exercises', 'id');
SELECT fk_ok('public', 'comments', 'exercise_set_id', 'public', 'exercise_sets', 'id');
SELECT fk_ok('public', 'comments', 'workout_image_id', 'public', 'workout_images', 'id');

SELECT * FROM finish();

ROLLBACK;