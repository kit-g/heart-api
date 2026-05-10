BEGIN;

SELECT plan(12);

SELECT has_table('public'::name, 'exercise_translations'::name);

SELECT columns_are(
               'public',
               'exercise_translations',
               ARRAY [
                   'exercise_id',
                   'locale',
                   'name',
                   'instructions'
                   ]
       );

SELECT col_type_is('public'::name, 'exercise_translations'::name, 'exercise_id'::name, 'uuid'::name);
SELECT col_type_is('public'::name, 'exercise_translations'::name, 'locale'::name, 'text'::name);
SELECT col_type_is('public'::name, 'exercise_translations'::name, 'name'::name, 'text'::name);
SELECT col_type_is('public'::name, 'exercise_translations'::name, 'instructions'::name, 'text'::name);

SELECT has_pk('public'::name, 'exercise_translations'::name, 'exercise_translations has a primary key');
SELECT col_is_pk('public'::name, 'exercise_translations'::name, ARRAY ['exercise_id', 'locale'], '(exercise_id, locale) is the composite primary key');

SELECT col_not_null('public'::name, 'exercise_translations'::name, 'exercise_id'::name);
SELECT col_not_null('public'::name, 'exercise_translations'::name, 'locale'::name);
SELECT col_not_null('public'::name, 'exercise_translations'::name, 'name'::name);

SELECT fk_ok('public', 'exercise_translations', 'exercise_id', 'public', 'exercises', 'id');

SELECT * FROM finish();

ROLLBACK;
