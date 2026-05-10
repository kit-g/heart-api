BEGIN;

SELECT plan(18);

SELECT has_table('public'::name, 'chart_preferences'::name);

SELECT columns_are(
               'public',
               'chart_preferences',
               ARRAY [
                   'id',
                   'user_id',
                   'exercise_id',
                   'chart_type',
                   'created_at'
                   ]
       );

SELECT col_type_is('public'::name, 'chart_preferences'::name, 'id'::name, 'uuid'::name);
SELECT col_type_is('public'::name, 'chart_preferences'::name, 'user_id'::name, 'text'::name);
SELECT col_type_is('public'::name, 'chart_preferences'::name, 'exercise_id'::name, 'text'::name);
SELECT col_type_is('public'::name, 'chart_preferences'::name, 'chart_type'::name, 'text'::name);
SELECT col_type_is('public'::name, 'chart_preferences'::name, 'created_at'::name, 'timestamp with time zone'::name);

SELECT has_pk('public'::name, 'chart_preferences'::name, 'chart_preferences has a primary key');
SELECT col_is_pk('public'::name, 'chart_preferences'::name, 'id'::name, 'id is the primary key');

SELECT col_not_null('public'::name, 'chart_preferences'::name, 'id'::name);
SELECT col_not_null('public'::name, 'chart_preferences'::name, 'user_id'::name);
SELECT col_not_null('public'::name, 'chart_preferences'::name, 'exercise_id'::name);
SELECT col_not_null('public'::name, 'chart_preferences'::name, 'chart_type'::name);
SELECT col_not_null('public'::name, 'chart_preferences'::name, 'created_at'::name);

SELECT col_default_is('public', 'chart_preferences', 'id', 'uuidv7()', 'id default is uuidv7()');
SELECT col_default_is('public', 'chart_preferences', 'created_at', 'now()', 'created_at default is now()');

SELECT fk_ok('public', 'chart_preferences', 'user_id', 'public', 'profiles', 'id');

SELECT col_is_unique('public'::name, 'chart_preferences'::name, ARRAY ['user_id', 'exercise_id']);

SELECT * FROM finish();

ROLLBACK;
