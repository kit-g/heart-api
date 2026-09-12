BEGIN;

SELECT plan(23);

SELECT has_table('public'::name, 'exercise_preferences'::name);

SELECT columns_are(
               'public',
               'exercise_preferences',
               ARRAY [
                   'id',
                   'user_id',
                   'exercise_id',
                   'chart_type',
                   'unit_system',
                   'rest_timer',
                   'note',
                   'created_at'
                   ]
       );

SELECT col_type_is('public'::name, 'exercise_preferences'::name, 'id'::name, 'uuid'::name);
SELECT col_type_is('public'::name, 'exercise_preferences'::name, 'user_id'::name, 'text'::name);
SELECT col_type_is('public'::name, 'exercise_preferences'::name, 'exercise_id'::name, 'uuid'::name);
SELECT col_type_is('public'::name, 'exercise_preferences'::name, 'chart_type'::name, 'text'::name);
SELECT col_type_is('public'::name, 'exercise_preferences'::name, 'unit_system'::name, 'text'::name);
SELECT col_type_is('public'::name, 'exercise_preferences'::name, 'rest_timer'::name, 'integer'::name);
SELECT col_type_is('public'::name, 'exercise_preferences'::name, 'note'::name, 'text'::name);
SELECT col_type_is('public'::name, 'exercise_preferences'::name, 'created_at'::name, 'timestamp with time zone'::name);

SELECT has_pk('public'::name, 'exercise_preferences'::name, 'exercise_preferences has a primary key');
SELECT col_is_pk('public'::name, 'exercise_preferences'::name, 'id'::name, 'id is the primary key');

SELECT col_not_null('public'::name, 'exercise_preferences'::name, 'id'::name);
SELECT col_not_null('public'::name, 'exercise_preferences'::name, 'user_id'::name);
SELECT col_not_null('public'::name, 'exercise_preferences'::name, 'exercise_id'::name);
SELECT col_not_null('public'::name, 'exercise_preferences'::name, 'created_at'::name);

SELECT col_default_is('public', 'exercise_preferences', 'id', 'uuidv7()', 'id default is uuidv7()');
SELECT col_default_is('public', 'exercise_preferences', 'created_at', 'now()', 'created_at default is now()');

SELECT fk_ok('public', 'exercise_preferences', 'user_id', 'public', 'profiles', 'id');
SELECT fk_ok('public', 'exercise_preferences', 'exercise_id', 'public', 'exercises', 'id');

SELECT col_is_unique('public'::name, 'exercise_preferences'::name, ARRAY ['user_id', 'exercise_id']);

-- The pinned note's bound. Seeded here rather than asserted on the constraint
-- definition: what matters is which values the table actually accepts.
DO
$$
BEGIN
    PERFORM create_test_profile('ep-note-user');
    PERFORM create_test_exercise('EP Note Bench', _user_id := 'ep-note-user');
END
$$;

SELECT lives_ok(
               $$
               INSERT INTO exercise_preferences (user_id, exercise_id, note)
               VALUES (
                   'ep-note-user',
                   (SELECT id FROM exercises WHERE name = 'EP Note Bench'),
                   repeat('x', 200)
               )
               $$,
               'a note of exactly 200 chars is allowed'
       );

SELECT throws_ok(
               $$
               INSERT INTO exercise_preferences (user_id, exercise_id, note)
               VALUES (
                   'ep-note-user',
                   (SELECT id FROM exercises WHERE name = 'EP Note Bench'),
                   repeat('x', 201)
               )
               $$,
               '23514',
               NULL,
               'a note over 200 chars is rejected'
       );

SELECT * FROM finish();

ROLLBACK;
