BEGIN;

SELECT plan(33);

SELECT has_table('public'::name, 'reactions'::name);

SELECT columns_are(
               'public',
               'reactions',
               ARRAY [
                   'id',
                   'author_id',
                   'kind',
                   'workout_id',
                   'workout_exercise_id',
                   'exercise_set_id',
                   'workout_image_id',
                   'created_at'
                   ]
       );

SELECT col_type_is('public'::name, 'reactions'::name, 'id'::name, 'uuid'::name);
SELECT col_type_is('public'::name, 'reactions'::name, 'author_id'::name, 'text'::name);
SELECT col_type_is('public'::name, 'reactions'::name, 'kind'::name, 'text'::name);
SELECT col_type_is('public'::name, 'reactions'::name, 'workout_id'::name, 'uuid'::name);
SELECT col_type_is('public'::name, 'reactions'::name, 'workout_exercise_id'::name, 'uuid'::name);
SELECT col_type_is('public'::name, 'reactions'::name, 'exercise_set_id'::name, 'uuid'::name);
SELECT col_type_is('public'::name, 'reactions'::name, 'workout_image_id'::name, 'uuid'::name);
SELECT col_type_is('public'::name, 'reactions'::name, 'created_at'::name, 'timestamp with time zone'::name);

SELECT has_pk('public'::name, 'reactions'::name);
SELECT col_is_pk('public'::name, 'reactions'::name, 'id'::name);

SELECT col_not_null('public'::name, 'reactions'::name, 'id'::name);
SELECT col_not_null('public'::name, 'reactions'::name, 'author_id'::name);
SELECT col_not_null('public'::name, 'reactions'::name, 'kind'::name);
SELECT col_not_null('public'::name, 'reactions'::name, 'created_at'::name);

SELECT col_default_is('public', 'reactions', 'id', 'uuidv7()', 'id defaults to a v7');
SELECT col_default_is('public', 'reactions', 'created_at', 'now()', 'created_at defaults to now()');

SELECT fk_ok('public', 'reactions', 'author_id', 'public', 'profiles', 'id');
SELECT fk_ok('public', 'reactions', 'workout_id', 'public', 'workouts', 'id');
SELECT fk_ok('public', 'reactions', 'workout_exercise_id', 'public', 'workout_exercises', 'id');
SELECT fk_ok('public', 'reactions', 'exercise_set_id', 'public', 'exercise_sets', 'id');
SELECT fk_ok('public', 'reactions', 'workout_image_id', 'public', 'workout_images', 'id');

SELECT has_index('public'::name, 'reactions'::name, 'reactions_workout_key'::name);
SELECT has_index('public'::name, 'reactions'::name, 'reactions_workout_exercise_key'::name);
SELECT has_index('public'::name, 'reactions'::name, 'reactions_exercise_set_key'::name);
SELECT has_index('public'::name, 'reactions'::name, 'reactions_workout_image_key'::name);
SELECT has_index('public'::name, 'reactions'::name, 'reactions_author_idx'::name);

SELECT index_is_unique('public'::name, 'reactions'::name, 'reactions_workout_key'::name);
SELECT index_is_unique('public'::name, 'reactions'::name, 'reactions_workout_exercise_key'::name);
SELECT index_is_unique('public'::name, 'reactions'::name, 'reactions_exercise_set_key'::name);
SELECT index_is_unique('public'::name, 'reactions'::name, 'reactions_workout_image_key'::name);

SELECT has_check('public'::name, 'reactions'::name, 'reactions has its checks');

SELECT * FROM finish();

ROLLBACK;
