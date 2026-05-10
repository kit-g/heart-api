BEGIN;

SELECT plan(17);

SELECT has_table('public'::name, 'workout_images'::name);

SELECT columns_are(
               'public',
               'workout_images',
               ARRAY [
                   'id',
                   'workout_id',
                   'user_id',
                   'key',
                   'created_at'
                   ]
       );

SELECT col_type_is('public'::name, 'workout_images'::name, 'id'::name, 'uuid'::name);
SELECT col_type_is('public'::name, 'workout_images'::name, 'workout_id'::name, 'uuid'::name);
SELECT col_type_is('public'::name, 'workout_images'::name, 'user_id'::name, 'text'::name);
SELECT col_type_is('public'::name, 'workout_images'::name, 'key'::name, 'text'::name);
SELECT col_type_is('public'::name, 'workout_images'::name, 'created_at'::name, 'timestamp with time zone'::name);

SELECT has_pk('public'::name, 'workout_images'::name, 'workout_images has a primary key');
SELECT col_is_pk('public'::name, 'workout_images'::name, 'id'::name, 'id is the primary key');

SELECT col_not_null('public'::name, 'workout_images'::name, 'id'::name);
SELECT col_not_null('public'::name, 'workout_images'::name, 'workout_id'::name);
SELECT col_not_null('public'::name, 'workout_images'::name, 'user_id'::name);
SELECT col_not_null('public'::name, 'workout_images'::name, 'key'::name);

SELECT col_default_is('public', 'workout_images', 'id', 'uuidv7()', 'id default is uuidv7()');
SELECT col_default_is('public', 'workout_images', 'created_at', 'now()', 'created_at default is now()');

SELECT fk_ok('public', 'workout_images', 'workout_id', 'public', 'workouts', 'id');

SELECT col_is_unique('public'::name, 'workout_images'::name, ARRAY ['key']);

SELECT * FROM finish();

ROLLBACK;
