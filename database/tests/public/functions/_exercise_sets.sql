BEGIN;

CREATE OR REPLACE FUNCTION test__exercise_sets_signature() RETURNS SETOF TEXT AS
$$
BEGIN
    RETURN NEXT has_function('public'::name, '_exercise_sets'::name);
    RETURN NEXT function_lang_is('public'::name, '_exercise_sets'::name, ARRAY ['uuid'::name], 'sql'::name);
    RETURN NEXT function_returns('public'::name, '_exercise_sets'::name, ARRAY ['uuid'::name], 'jsonb');
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test__exercise_sets_returns_empty_for_unknown_we() RETURNS SETOF TEXT AS
$$
BEGIN
    RETURN NEXT is(_exercise_sets(gen_random_uuid()), '[]'::jsonb, 'returns [] when no sets match');
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test__exercise_sets_returns_one_set_per_row() RETURNS SETOF TEXT AS
$$
DECLARE
    _user_id  TEXT;
    _ex_id    UUID;
    _w_id     UUID;
    _we_id    UUID;
    _result   JSONB;
BEGIN
    _user_id := create_test_profile();
    _ex_id   := create_test_exercise(_user_id := _user_id);
    _w_id    := create_test_workout(_user_id => _user_id);
    _we_id   := create_test_workout_exercise(_w_id, _ex_id, 0);

    PERFORM create_test_exercise_set(_we_id, 0, 100, 5);
    PERFORM create_test_exercise_set(_we_id, 1, 100, 5);
    PERFORM create_test_exercise_set(_we_id, 2, 95, 5);

    _result := _exercise_sets(_we_id);

    RETURN NEXT is(jsonb_typeof(_result), 'array', 'returns an array');
    RETURN NEXT is(jsonb_array_length(_result), 3, 'returns one entry per set');
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test__exercise_sets_orders_by_set_order() RETURNS SETOF TEXT AS
$$
DECLARE
    _user_id TEXT;
    _ex_id   UUID;
    _w_id    UUID;
    _we_id   UUID;
    _result  JSONB;
BEGIN
    _user_id := create_test_profile();
    _ex_id   := create_test_exercise(_user_id := _user_id);
    _w_id    := create_test_workout(_user_id => _user_id);
    _we_id   := create_test_workout_exercise(_w_id, _ex_id, 0);

    -- inserted out of order
    PERFORM create_test_exercise_set(_we_id, 2, 95, 5);
    PERFORM create_test_exercise_set(_we_id, 0, 100, 5);
    PERFORM create_test_exercise_set(_we_id, 1, 100, 5);

    _result := _exercise_sets(_we_id);

    RETURN NEXT is((_result -> 0 ->> 'set_order')::int, 0, 'first by set_order');
    RETURN NEXT is((_result -> 1 ->> 'set_order')::int, 1, 'second by set_order');
    RETURN NEXT is((_result -> 2 ->> 'set_order')::int, 2, 'third by set_order');
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test__exercise_sets_emits_correct_shape() RETURNS SETOF TEXT AS
$$
DECLARE
    _user_id TEXT;
    _ex_id   UUID;
    _w_id    UUID;
    _we_id   UUID;
    _result  JSONB;
BEGIN
    _user_id := create_test_profile();
    _ex_id   := create_test_exercise(_user_id := _user_id);
    _w_id    := create_test_workout(_user_id => _user_id);
    _we_id   := create_test_workout_exercise(_w_id, _ex_id, 0);

    PERFORM create_test_exercise_set(
        _workout_exercise_id => _we_id,
        _set_order => 0,
        _weight => 135,
        _reps => 5,
        _completed => true
    );
    UPDATE exercise_sets
    SET started_at   = '2026-08-08T10:00:00Z',
        completed_at = '2026-08-08T10:01:30Z'
    WHERE workout_exercise_id = _we_id;

    _result := _exercise_sets(_we_id);

    RETURN NEXT ok(
        TRUE = ALL (SELECT validate_format_exercise_set(_result -> 0)),
        'set JSON matches expected shape'
    );
    RETURN NEXT is((_result -> 0 ->> 'weight')::real, 135::real, 'weight is preserved');
    RETURN NEXT is((_result -> 0 ->> 'reps')::int, 5, 'reps is preserved');
    RETURN NEXT is((_result -> 0 ->> 'completed')::boolean, TRUE, 'completed is preserved');
    RETURN NEXT is(
        (_result -> 0 ->> 'started_at')::timestamptz,
        '2026-08-08T10:00:00Z'::timestamptz,
        'started_at is preserved'
    );
    RETURN NEXT is(
        (_result -> 0 ->> 'completed_at')::timestamptz,
        '2026-08-08T10:01:30Z'::timestamptz,
        'completed_at is preserved'
    );
END
$$ LANGUAGE plpgsql;

SELECT * FROM runtests();

ROLLBACK;
