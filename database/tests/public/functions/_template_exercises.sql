BEGIN;

CREATE OR REPLACE FUNCTION test__template_exercises_signature() RETURNS SETOF TEXT AS
$$
BEGIN
    RETURN NEXT has_function('public'::name, '_template_exercises'::name);
    RETURN NEXT function_lang_is('public'::name, '_template_exercises'::name, ARRAY ['uuid'::name], 'sql'::name);
    RETURN NEXT function_returns('public'::name, '_template_exercises'::name, ARRAY ['uuid'::name], 'jsonb');
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test__template_exercises_returns_empty_array_for_unknown() RETURNS SETOF TEXT AS
$$
BEGIN
    RETURN NEXT is(_template_exercises(gen_random_uuid()), '[]'::jsonb, 'returns [] when no exercises match');
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test__template_exercises_returns_and_orders() RETURNS SETOF TEXT AS
$$
DECLARE
    _user_id TEXT;
    _ex_a    UUID;
    _ex_b    UUID;
    _ex_c    UUID;
    _t_id    UUID;
    _result  JSONB;
BEGIN
    _user_id := create_test_profile();
    _ex_a    := create_test_exercise(_user_id := _user_id);
    _ex_b    := create_test_exercise(_user_id := _user_id);
    _ex_c    := create_test_exercise(_user_id := _user_id);
    _t_id    := create_test_template(_user_id => _user_id);

    PERFORM create_test_template_exercise(_t_id, _ex_b, 2);
    PERFORM create_test_template_exercise(_t_id, _ex_a, 0);
    PERFORM create_test_template_exercise(_t_id, _ex_c, 1);

    _result := _template_exercises(_t_id);

    RETURN NEXT is(jsonb_array_length(_result), 3, 'one entry per template_exercise');
    RETURN NEXT is((_result -> 0 ->> 'exercise_order')::int, 0, 'first by exercise_order');
    RETURN NEXT is((_result -> 1 ->> 'exercise_order')::int, 1, 'second by exercise_order');
    RETURN NEXT is((_result -> 2 ->> 'exercise_order')::int, 2, 'third by exercise_order');
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test__template_exercises_emits_correct_shape() RETURNS SETOF TEXT AS
$$
DECLARE
    _user_id TEXT;
    _ex_id   UUID;
    _t_id    UUID;
    _te_id   UUID;
    _result  JSONB;
BEGIN
    _user_id := create_test_profile();
    _ex_id   := create_test_exercise('Squat (Barbell)', 'Barbell', 'Legs', _user_id);
    _t_id    := create_test_template(_user_id => _user_id);
    _te_id   := create_test_template_exercise(_t_id, _ex_id, 0);
    PERFORM create_test_template_set(_te_id, 0, 185, 5);

    _result := _template_exercises(_t_id);

    RETURN NEXT ok(
        TRUE = ALL (SELECT validate_format_template_exercise(_result -> 0)),
        'template_exercise JSON matches expected shape'
    );
    RETURN NEXT is(_result -> 0 -> 'exercise' ->> 'name', 'Squat (Barbell)', 'exercise.name preserved');
    RETURN NEXT is(_result -> 0 -> 'exercise' ->> 'category', 'Barbell', 'exercise.category preserved');
    RETURN NEXT is(_result -> 0 -> 'exercise' ->> 'target', 'Legs', 'exercise.target preserved');
    RETURN NEXT is(jsonb_array_length(_result -> 0 -> 'sets'), 1, 'sets array populated');
END
$$ LANGUAGE plpgsql;

SELECT * FROM runtests();

ROLLBACK;
