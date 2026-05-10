BEGIN;

CREATE OR REPLACE FUNCTION test__template_exercise_sets_signature() RETURNS SETOF TEXT AS
$$
BEGIN
    RETURN NEXT has_function('public'::name, '_template_exercise_sets'::name);
    RETURN NEXT function_lang_is('public'::name, '_template_exercise_sets'::name, ARRAY ['uuid'::name], 'sql'::name);
    RETURN NEXT function_returns('public'::name, '_template_exercise_sets'::name, ARRAY ['uuid'::name], 'jsonb');
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test__template_exercise_sets_returns_empty_array_for_unknown() RETURNS SETOF TEXT AS
$$
BEGIN
    RETURN NEXT is(_template_exercise_sets(gen_random_uuid()), '[]'::jsonb, 'returns [] when no sets match');
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test__template_exercise_sets_returns_and_orders() RETURNS SETOF TEXT AS
$$
DECLARE
    _user_id TEXT;
    _ex_id   UUID;
    _t_id    UUID;
    _te_id   UUID;
    _result  JSONB;
BEGIN
    _user_id := create_test_profile();
    _ex_id   := create_test_exercise(_user_id := _user_id);
    _t_id    := create_test_template(_user_id => _user_id);
    _te_id   := create_test_template_exercise(_t_id, _ex_id, 0);

    PERFORM create_test_template_set(_te_id, 2, 95, 5);
    PERFORM create_test_template_set(_te_id, 0, 100, 5);
    PERFORM create_test_template_set(_te_id, 1, 100, 5);

    _result := _template_exercise_sets(_te_id);

    RETURN NEXT is(jsonb_array_length(_result), 3, 'returns one entry per set');
    RETURN NEXT is((_result -> 0 ->> 'set_order')::int, 0, 'ordered by set_order');
    RETURN NEXT is((_result -> 1 ->> 'set_order')::int, 1, 'ordered by set_order');
    RETURN NEXT is((_result -> 2 ->> 'set_order')::int, 2, 'ordered by set_order');
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test__template_exercise_sets_emits_correct_shape() RETURNS SETOF TEXT AS
$$
DECLARE
    _user_id TEXT;
    _ex_id   UUID;
    _t_id    UUID;
    _te_id   UUID;
    _result  JSONB;
BEGIN
    _user_id := create_test_profile();
    _ex_id   := create_test_exercise(_user_id := _user_id);
    _t_id    := create_test_template(_user_id => _user_id);
    _te_id   := create_test_template_exercise(_t_id, _ex_id, 0);
    PERFORM create_test_template_set(_te_id, 0, 135, 5);

    _result := _template_exercise_sets(_te_id);

    RETURN NEXT ok(
        TRUE = ALL (SELECT validate_format_template_set(_result -> 0)),
        'template set JSON matches expected shape'
    );
    -- template sets must NOT have completed/started_at (those are workout-side concerns)
    RETURN NEXT ok(NOT (_result -> 0 ? 'completed'), 'no completed key on template set');
    RETURN NEXT ok(NOT (_result -> 0 ? 'started_at'), 'no started_at key on template set');
END
$$ LANGUAGE plpgsql;

SELECT * FROM runtests();

ROLLBACK;
