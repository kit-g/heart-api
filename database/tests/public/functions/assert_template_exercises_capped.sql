-- The per-template ceiling on exercise rows — templates mirror workouts, so
-- this is assert_workout_exercises_capped's twin.

BEGIN;

CREATE OR REPLACE FUNCTION test__template_exercises_cap_signature() RETURNS SETOF TEXT AS
$$
BEGIN
    RETURN NEXT has_function('public'::name, 'assert_template_exercises_capped'::name);
    RETURN NEXT function_returns('public'::name, 'assert_template_exercises_capped'::name, 'trigger');
    RETURN NEXT function_lang_is('public'::name, 'assert_template_exercises_capped'::name, 'plpgsql'::name);
    RETURN NEXT has_trigger('public'::name, 'template_exercises'::name, 'template_exercises_template_cap'::name);
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test__template_exercises_cap_enforced() RETURNS SETOF TEXT AS
$$
DECLARE
    _user_id     TEXT;
    _exercise_id UUID;
    _template_id UUID;
    _other_id    UUID;
BEGIN
    _user_id := create_test_profile();
    _exercise_id := create_test_exercise();
    _template_id := create_test_template(_user_id => _user_id);
    _other_id := create_test_template(_user_id => _user_id);

    RETURN NEXT is(
        (SELECT count(*) FROM template_exercises WHERE template_id = _template_id),
        0::bigint,
        'no exercise rows yet'
    );

    RETURN NEXT lives_ok(
        format(
            'INSERT INTO template_exercises (template_id, exercise_id, exercise_order) SELECT %L::uuid, %L::uuid, n FROM generate_series(0, 999) n',
            _template_id, _exercise_id
        ),
        'a template can fill to exactly the cap'
    );

    RETURN NEXT throws_ok(
        format(
            'INSERT INTO template_exercises (template_id, exercise_id, exercise_order) VALUES (%L, %L, 1000)',
            _template_id, _exercise_id
        ),
        '23514',
        format('exercises per template cap (1000) exceeded for template %s', _template_id),
        'the row crossing the cap is refused'
    );

    RETURN NEXT lives_ok(
        format(
            'INSERT INTO template_exercises (template_id, exercise_id, exercise_order) VALUES (%L, %L, 0)',
            _other_id, _exercise_id
        ),
        'one template at the cap does not block another'
    );
END
$$ LANGUAGE plpgsql;

SELECT * FROM runtests();

ROLLBACK;
