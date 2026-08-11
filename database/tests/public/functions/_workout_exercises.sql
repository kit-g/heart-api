BEGIN;

CREATE OR REPLACE FUNCTION test__we_signature() RETURNS SETOF TEXT AS
$$
BEGIN
    RETURN NEXT has_function('public'::name, '_workout_exercises'::name);
    RETURN NEXT function_lang_is('public'::name, '_workout_exercises'::name, ARRAY ['uuid'::name], 'sql'::name);
    RETURN NEXT function_returns('public'::name, '_workout_exercises'::name, ARRAY ['uuid'::name], 'jsonb');
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test__we_returns_empty_array_for_unknown_workout() RETURNS SETOF TEXT AS
$$
BEGIN
    RETURN NEXT is(_workout_exercises(gen_random_uuid()), '[]'::jsonb, 'returns [] when no exercises match');
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test__we_returns_one_per_exercise() RETURNS SETOF TEXT AS
$$
DECLARE
    _user_id TEXT;
    _ex_a    UUID;
    _ex_b    UUID;
    _w_id    UUID;
    _result  JSONB;
BEGIN
    _user_id := create_test_profile();
    _ex_a    := create_test_exercise(_user_id := _user_id);
    _ex_b    := create_test_exercise(_user_id := _user_id);
    _w_id    := create_test_workout(_user_id => _user_id);

    PERFORM create_test_workout_exercise(_w_id, _ex_a, 0);
    PERFORM create_test_workout_exercise(_w_id, _ex_b, 1);

    _result := _workout_exercises(_w_id);

    RETURN NEXT is(jsonb_typeof(_result), 'array', 'returns an array');
    RETURN NEXT is(jsonb_array_length(_result), 2, 'one entry per workout_exercise');
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test__we_orders_by_exercise_order() RETURNS SETOF TEXT AS
$$
DECLARE
    _user_id TEXT;
    _ex_a    UUID;
    _ex_b    UUID;
    _ex_c    UUID;
    _w_id    UUID;
    _result  JSONB;
BEGIN
    _user_id := create_test_profile();
    _ex_a    := create_test_exercise(_user_id := _user_id);
    _ex_b    := create_test_exercise(_user_id := _user_id);
    _ex_c    := create_test_exercise(_user_id := _user_id);
    _w_id    := create_test_workout(_user_id => _user_id);

    PERFORM create_test_workout_exercise(_w_id, _ex_b, 2);
    PERFORM create_test_workout_exercise(_w_id, _ex_a, 0);
    PERFORM create_test_workout_exercise(_w_id, _ex_c, 1);

    _result := _workout_exercises(_w_id);

    RETURN NEXT is((_result -> 0 ->> 'exercise_order')::int, 0, 'first by exercise_order');
    RETURN NEXT is((_result -> 1 ->> 'exercise_order')::int, 1, 'second by exercise_order');
    RETURN NEXT is((_result -> 2 ->> 'exercise_order')::int, 2, 'third by exercise_order');
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test__we_emits_correct_shape() RETURNS SETOF TEXT AS
$$
DECLARE
    _user_id TEXT;
    _ex_id   UUID;
    _w_id    UUID;
    _we_id   UUID;
    _result  JSONB;
BEGIN
    _user_id := create_test_profile();
    _ex_id   := create_test_exercise('Bench Press', 'Barbell', 'Chest', _user_id);
    _w_id    := create_test_workout(_user_id => _user_id);
    _we_id   := create_test_workout_exercise(_w_id, _ex_id, 0);
    PERFORM create_test_exercise_set(_we_id, 0, 135, 5);
    UPDATE workout_exercises SET met = 5.5, note = 'do one hand at a time' WHERE id = _we_id;

    _result := _workout_exercises(_w_id);

    RETURN NEXT ok(
        TRUE = ALL (SELECT validate_format_workout_exercise(_result -> 0)),
        'workout_exercise JSON matches expected shape'
    );
    RETURN NEXT is(_result -> 0 -> 'exercise' ->> 'name', 'Bench Press', 'exercise.name preserved');
    RETURN NEXT is(_result -> 0 -> 'exercise' ->> 'category', 'Barbell', 'exercise.category preserved');
    RETURN NEXT is(_result -> 0 -> 'exercise' ->> 'target', 'Chest', 'exercise.target preserved');
    RETURN NEXT is((_result -> 0 ->> 'met')::real, 5.5::real, 'met preserved');
    RETURN NEXT is(_result -> 0 ->> 'note', 'do one hand at a time', 'note preserved');
    RETURN NEXT is(jsonb_array_length(_result -> 0 -> 'sets'), 1, 'sets array populated');
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test__we_includes_workout_exercise_with_zero_sets() RETURNS SETOF TEXT AS
$$
DECLARE
    _user_id TEXT;
    _ex_id   UUID;
    _w_id    UUID;
    _result  JSONB;
BEGIN
    _user_id := create_test_profile();
    _ex_id   := create_test_exercise(_user_id := _user_id);
    _w_id    := create_test_workout(_user_id => _user_id);
    PERFORM create_test_workout_exercise(_w_id, _ex_id, 0);

    _result := _workout_exercises(_w_id);

    RETURN NEXT is(jsonb_array_length(_result), 1, 'workout_exercise without sets still returned');
    RETURN NEXT is(jsonb_array_length(_result -> 0 -> 'sets'), 0, 'sets is empty array');
END
$$ LANGUAGE plpgsql;

SELECT * FROM runtests();

ROLLBACK;
