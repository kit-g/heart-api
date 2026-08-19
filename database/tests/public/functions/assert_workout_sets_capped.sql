-- The per-workout ceiling on sets: an INSERT into exercise_sets that would
-- push any touched workout past 1000 sets is refused wholesale, counting
-- across all of the workout's exercises; other workouts stay unaffected.

BEGIN;

CREATE OR REPLACE FUNCTION test__workout_sets_cap_signature() RETURNS SETOF TEXT AS
$$
BEGIN
    RETURN NEXT has_function('public'::name, 'assert_workout_sets_capped'::name);
    RETURN NEXT function_returns('public'::name, 'assert_workout_sets_capped'::name, 'trigger');
    RETURN NEXT function_lang_is('public'::name, 'assert_workout_sets_capped'::name, 'plpgsql'::name);
    RETURN NEXT has_trigger('public'::name, 'exercise_sets'::name, 'exercise_sets_workout_cap'::name);
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test__workout_sets_cap_enforced() RETURNS SETOF TEXT AS
$$
DECLARE
    _user_id     TEXT;
    _exercise_id UUID;
    _workout_id  UUID;
    _first_we    UUID;
    _second_we   UUID;
BEGIN
    _user_id := create_test_profile();
    _exercise_id := create_test_exercise();
    _workout_id := create_test_workout(_user_id => _user_id);
    _first_we := create_test_workout_exercise(_workout_id, _exercise_id, 0);
    _second_we := create_test_workout_exercise(_workout_id, _exercise_id, 1);

    RETURN NEXT is(
        (SELECT count(*) FROM exercise_sets WHERE workout_exercise_id IN (_first_we, _second_we)),
        0::bigint,
        'no sets yet'
    );

    -- the cap counts the workout's sets across its exercises: 400 + 600 = 1000
    INSERT INTO exercise_sets (workout_exercise_id, set_order)
    SELECT _first_we, n FROM generate_series(0, 399) n;
    RETURN NEXT lives_ok(
        format(
            'INSERT INTO exercise_sets (workout_exercise_id, set_order) SELECT %L::uuid, n FROM generate_series(0, 599) n',
            _second_we
        ),
        'a workout can fill to exactly the cap'
    );

    RETURN NEXT throws_ok(
        format('INSERT INTO exercise_sets (workout_exercise_id, set_order) VALUES (%L, 600)', _second_we),
        '23514',
        format('sets per workout cap (1000) exceeded for workout %s', _workout_id),
        'the set crossing the cap is refused'
    );
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test__workout_sets_cap_is_per_workout() RETURNS SETOF TEXT AS
$$
DECLARE
    _user_id     TEXT;
    _exercise_id UUID;
    _full_we     UUID;
    _other_we    UUID;
BEGIN
    _user_id := create_test_profile();
    _exercise_id := create_test_exercise();
    _full_we := create_test_workout_exercise(create_test_workout(_user_id => _user_id), _exercise_id, 0);
    _other_we := create_test_workout_exercise(create_test_workout(_user_id => _user_id), _exercise_id, 0);

    INSERT INTO exercise_sets (workout_exercise_id, set_order)
    SELECT _full_we, n FROM generate_series(0, 999) n;

    RETURN NEXT lives_ok(
        format('INSERT INTO exercise_sets (workout_exercise_id, set_order) VALUES (%L, 0)', _other_we),
        'one workout at the cap does not block another'
    );
END
$$ LANGUAGE plpgsql;

SELECT * FROM runtests();

ROLLBACK;
