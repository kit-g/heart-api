BEGIN;

SELECT plan(43);

SELECT has_table('public'::name, 'workouts'::name);

SELECT columns_are(
               'public',
               'workouts',
               ARRAY [
                   'id',
                   'user_id',
                   'name',
                   'started_at',
                   'completed_at',
                   'calories',
                   'created_at',
                   'import_id',
                   'note',
                   'pauses',
                   'updated_at',
                   'changed_xid'
                   ]
       );

SELECT col_type_is('public'::name, 'workouts'::name, 'id'::name, 'uuid'::name);
SELECT col_type_is('public'::name, 'workouts'::name, 'user_id'::name, 'text'::name);
SELECT col_type_is('public'::name, 'workouts'::name, 'name'::name, 'text'::name);
SELECT col_type_is('public'::name, 'workouts'::name, 'started_at'::name, 'timestamp with time zone'::name);
SELECT col_type_is('public'::name, 'workouts'::name, 'completed_at'::name, 'timestamp with time zone'::name);
SELECT col_type_is('public'::name, 'workouts'::name, 'calories'::name, 'real'::name);
SELECT col_type_is('public'::name, 'workouts'::name, 'created_at'::name, 'timestamp with time zone'::name);
SELECT col_type_is('public'::name, 'workouts'::name, 'import_id'::name, 'text'::name);
SELECT col_type_is('public'::name, 'workouts'::name, 'note'::name, 'text'::name);
SELECT col_type_is('public'::name, 'workouts'::name, 'pauses'::name, 'jsonb'::name);

SELECT has_pk('public'::name, 'workouts'::name, 'workouts has a primary key');
SELECT col_is_pk('public'::name, 'workouts'::name, 'id'::name, 'id is the primary key');

SELECT col_not_null('public'::name, 'workouts'::name, 'id'::name);
SELECT col_not_null('public'::name, 'workouts'::name, 'user_id'::name);
SELECT col_not_null('public'::name, 'workouts'::name, 'created_at'::name);
SELECT col_not_null('public'::name, 'workouts'::name, 'pauses'::name);

SELECT col_default_is('public', 'workouts', 'id', 'uuidv7()', 'id default is uuidv7()');
SELECT col_default_is('public', 'workouts', 'created_at', 'now()', 'created_at default is now()');
SELECT col_default_is('public', 'workouts', 'pauses', '[]'::jsonb, 'pauses default to none');

SELECT fk_ok('public', 'workouts', 'user_id', 'public', 'profiles', 'id');

SELECT has_index('public'::name, 'workouts'::name, 'workouts_user_id_idx'::name);
SELECT has_index('public'::name, 'workouts'::name, 'workouts_user_changed_idx'::name);
SELECT col_type_is('public'::name, 'workouts'::name, 'updated_at'::name, 'timestamp with time zone'::name);
SELECT col_not_null('public'::name, 'workouts'::name, 'updated_at'::name);
SELECT col_default_is('public', 'workouts', 'updated_at', 'now()', 'updated_at defaults to now()');
SELECT col_type_is('public'::name, 'workouts'::name, 'changed_xid'::name, 'xid8'::name);
SELECT col_not_null('public'::name, 'workouts'::name, 'changed_xid'::name);
SELECT col_default_is('public', 'workouts', 'changed_xid', 'pg_current_xact_id()', 'changed_xid defaults to the writing transaction');
SELECT has_index('public'::name, 'workouts'::name, 'workouts_user_import_id_idx'::name);
SELECT index_is_unique('public'::name, 'workouts'::name, 'workouts_user_import_id_idx'::name);

-- fixture for the CHECK-constraint assertions below
DO
$$
BEGIN
    PERFORM create_test_profile('w-check-user');
END
$$;

SELECT lives_ok(
               $$ INSERT INTO workouts (user_id, calories) VALUES ('w-check-user', 0) $$,
               'zero calories are allowed'
       );

SELECT throws_ok(
               $$ INSERT INTO workouts (user_id, calories) VALUES ('w-check-user', -120) $$,
               '23514',
               NULL,
               'negative calories are rejected'
       );

SELECT lives_ok(
               $$ INSERT INTO workouts (user_id, note) VALUES ('w-check-user', repeat('n', 1000)) $$,
               'a 1000-char note is allowed'
       );

SELECT throws_ok(
               $$ INSERT INTO workouts (user_id, note) VALUES ('w-check-user', repeat('n', 1001)) $$,
               '23514',
               NULL,
               'a note over 1000 chars is rejected'
       );

SELECT throws_ok(
               $$ INSERT INTO workouts (user_id, note) VALUES ('w-check-user', '') $$,
               '23514',
               NULL,
               'an empty note is rejected; no note is NULL'
       );

SELECT lives_ok(
               $$ INSERT INTO workouts (user_id, started_at, completed_at, pauses)
                  VALUES ('w-check-user', '2026-10-03T18:00:00Z', '2026-10-03T19:00:00Z',
                          '[{"start": "2026-10-03T18:10:00Z", "end": "2026-10-03T18:20:00Z"},
                            {"start": "2026-10-03T18:20:00Z", "end": "2026-10-03T18:25:00Z"}]') $$,
               'ordered pauses inside the workout are allowed, touching ends included'
       );

SELECT throws_ok(
               $$ INSERT INTO workouts (user_id, started_at, completed_at, pauses)
                  VALUES ('w-check-user', '2026-10-03T18:00:00Z', '2026-10-03T19:00:00Z',
                          '[{"start": "2026-10-03T18:50:00Z", "end": "2026-10-03T19:10:00Z"}]') $$,
               '23514',
               NULL,
               'a pause running past the end is rejected'
       );

SELECT throws_ok(
               $$ INSERT INTO workouts (user_id, started_at, completed_at, pauses)
                  VALUES ('w-check-user', '2026-10-03T18:00:00Z', '2026-10-03T19:00:00Z',
                          '[{"start": "2026-10-03T18:10:00Z", "end": "2026-10-03T18:30:00Z"},
                            {"start": "2026-10-03T18:20:00Z", "end": "2026-10-03T18:40:00Z"}]') $$,
               '23514',
               NULL,
               'overlapping pauses are rejected'
       );

SELECT throws_ok(
               $$ UPDATE workouts SET completed_at = '2026-10-03T18:15:00Z' WHERE user_id = 'w-check-user' AND pauses <> '[]' $$,
               '23514',
               NULL,
               'moving the end inside a stored pause is rejected unless the pauses are clipped'
       );

SELECT throws_ok(
               $$ INSERT INTO workouts (user_id, pauses) VALUES ('w-check-user', '{}') $$,
               '23514',
               NULL,
               'pauses are an array'
       );

-- first import row for the duplicate-identity assertion below
DO
$$
BEGIN
    INSERT INTO workouts (user_id, import_id) VALUES ('w-check-user', 'strong:2023-01-15 17:35:12#Push');
END
$$;

SELECT throws_ok(
               $$ INSERT INTO workouts (user_id, import_id) VALUES ('w-check-user', 'strong:2023-01-15 17:35:12#Push') $$,
               '23505',
               NULL,
               'the same import identity cannot land twice for one user'
       );

SELECT *
FROM finish();

ROLLBACK;
