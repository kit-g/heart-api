-- The per-user ceiling on bulk-imported workouts: an INSERT that would push a
-- user past 20000 rows with import_id IS NOT NULL is refused wholesale, while
-- app-created workouts (import_id IS NULL) pass untouched even at the cap.

BEGIN;

CREATE OR REPLACE FUNCTION test__imported_workouts_cap_signature() RETURNS SETOF TEXT AS
$$
BEGIN
    RETURN NEXT has_function('public'::name, 'assert_imported_workouts_capped'::name);
    RETURN NEXT function_returns('public'::name, 'assert_imported_workouts_capped'::name, 'trigger');
    RETURN NEXT function_lang_is('public'::name, 'assert_imported_workouts_capped'::name, 'plpgsql'::name);
    RETURN NEXT has_trigger('public'::name, 'workouts'::name, 'workouts_imported_cap'::name);
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test__imported_workouts_cap_enforced() RETURNS SETOF TEXT AS
$$
DECLARE
    _user_id TEXT;
BEGIN
    _user_id := create_test_profile();
    RETURN NEXT is((SELECT count(*) FROM workouts WHERE user_id = _user_id), 0::bigint, 'no workouts yet');

    -- filling to exactly the cap in one statement is allowed
    INSERT INTO workouts (user_id, started_at, import_id)
    SELECT _user_id, now() - (n || ' hours')::interval, 'strong:' || lpad(to_hex(n), 16, '0')
    FROM generate_series(1, 20000) n;
    RETURN NEXT is(
        (SELECT count(*) FROM workouts WHERE user_id = _user_id AND import_id IS NOT NULL),
        20000::bigint,
        'an import can fill the account to exactly the cap'
    );

    RETURN NEXT throws_ok(
        format(
            'INSERT INTO workouts (user_id, started_at, import_id) VALUES (%L, now(), %L)',
            _user_id, 'strong:0000000000000000'
        ),
        '23514',
        format('imported workouts cap (20000) exceeded for user %s', _user_id),
        'the import crossing the cap is refused'
    );

    RETURN NEXT lives_ok(
        format('INSERT INTO workouts (user_id, started_at) VALUES (%L, now())', _user_id),
        'app-created workouts are exempt even at the cap'
    );
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test__imported_workouts_cap_is_per_user() RETURNS SETOF TEXT AS
$$
DECLARE
    _full_id  TEXT;
    _other_id TEXT;
BEGIN
    _full_id := create_test_profile();
    _other_id := create_test_profile();

    INSERT INTO workouts (user_id, started_at, import_id)
    SELECT _full_id, now() - (n || ' hours')::interval, 'strong:' || lpad(to_hex(n), 16, '0')
    FROM generate_series(1, 20000) n;

    RETURN NEXT lives_ok(
        format(
            'INSERT INTO workouts (user_id, started_at, import_id) VALUES (%L, now(), %L)',
            _other_id, 'strong:0000000000000001'
        ),
        'one user at the cap does not block another''s import'
    );
END
$$ LANGUAGE plpgsql;

SELECT * FROM runtests();

ROLLBACK;
