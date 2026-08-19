-- The per-template ceiling on sets, counted across the template's exercises —
-- assert_workout_sets_capped's twin.

BEGIN;

CREATE OR REPLACE FUNCTION test__template_sets_cap_signature() RETURNS SETOF TEXT AS
$$
BEGIN
    RETURN NEXT has_function('public'::name, 'assert_template_sets_capped'::name);
    RETURN NEXT function_returns('public'::name, 'assert_template_sets_capped'::name, 'trigger');
    RETURN NEXT function_lang_is('public'::name, 'assert_template_sets_capped'::name, 'plpgsql'::name);
    RETURN NEXT has_trigger('public'::name, 'template_exercise_sets'::name, 'template_exercise_sets_template_cap'::name);
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test__template_sets_cap_enforced() RETURNS SETOF TEXT AS
$$
DECLARE
    _user_id     TEXT;
    _exercise_id UUID;
    _template_id UUID;
    _first_te    UUID;
    _second_te   UUID;
    _other_te    UUID;
BEGIN
    _user_id := create_test_profile();
    _exercise_id := create_test_exercise();
    _template_id := create_test_template(_user_id => _user_id);
    _first_te := create_test_template_exercise(_template_id, _exercise_id, 0);
    _second_te := create_test_template_exercise(_template_id, _exercise_id, 1);
    _other_te := create_test_template_exercise(create_test_template(_user_id => _user_id), _exercise_id, 0);

    RETURN NEXT is(
        (SELECT count(*) FROM template_exercise_sets WHERE template_exercise_id IN (_first_te, _second_te)),
        0::bigint,
        'no sets yet'
    );

    -- the cap counts the template's sets across its exercises: 400 + 600 = 1000
    INSERT INTO template_exercise_sets (template_exercise_id, set_order)
    SELECT _first_te, n FROM generate_series(0, 399) n;
    RETURN NEXT lives_ok(
        format(
            'INSERT INTO template_exercise_sets (template_exercise_id, set_order) SELECT %L::uuid, n FROM generate_series(0, 599) n',
            _second_te
        ),
        'a template can fill to exactly the cap'
    );

    RETURN NEXT throws_ok(
        format('INSERT INTO template_exercise_sets (template_exercise_id, set_order) VALUES (%L, 600)', _second_te),
        '23514',
        format('sets per template cap (1000) exceeded for template %s', _template_id),
        'the set crossing the cap is refused'
    );

    RETURN NEXT lives_ok(
        format('INSERT INTO template_exercise_sets (template_exercise_id, set_order) VALUES (%L, 0)', _other_te),
        'one template at the cap does not block another'
    );
END
$$ LANGUAGE plpgsql;

SELECT * FROM runtests();

ROLLBACK;
