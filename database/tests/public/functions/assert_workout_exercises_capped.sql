-- The per-workout ceiling on exercise rows: an INSERT into workout_exercises
-- that would push any touched workout past 1000 rows is refused wholesale;
-- other workouts stay unaffected. (Set-less exercise rows are exactly what
-- the sets ceiling cannot see — this is its companion.)

BEGIN;

CREATE OR REPLACE FUNCTION test__workout_exercises_cap_signature() RETURNS SETOF TEXT AS
$$
BEGIN
    RETURN NEXT has_function('public'::name, 'assert_workout_exercises_capped'::name);
    RETURN NEXT function_returns('public'::name, 'assert_workout_exercises_capped'::name, 'trigger');
    RETURN NEXT function_lang_is('public'::name, 'assert_workout_exercises_capped'::name, 'plpgsql'::name);
    RETURN NEXT has_trigger('public'::name, 'workout_exercises'::name, 'workout_exercises_workout_cap'::name);
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test__workout_exercises_cap_enforced() RETURNS SETOF TEXT AS
$$
DECLARE
    _user_id     TEXT;
    _exercise_id UUID;
    _workout_id  UUID;
    _other_id    UUID;
BEGIN
    _user_id := create_test_profile();
    _exercise_id := create_test_exercise();
    _workout_id := create_test_workout(_user_id => _user_id);
    _other_id := create_test_workout(_user_id => _user_id);

    RETURN NEXT is(
        (SELECT count(*) FROM workout_exercises WHERE workout_id = _workout_id),
        0::bigint,
        'no exercise rows yet'
    );

    RETURN NEXT lives_ok(
        format(
            'INSERT INTO workout_exercises (workout_id, exercise_id, exercise_order) SELECT %L::uuid, %L::uuid, n FROM generate_series(0, 999) n',
            _workout_id, _exercise_id
        ),
        'a workout can fill to exactly the cap'
    );

    RETURN NEXT throws_ok(
        format(
            'INSERT INTO workout_exercises (workout_id, exercise_id, exercise_order) VALUES (%L, %L, 1000)',
            _workout_id, _exercise_id
        ),
        '23514',
        format('exercises per workout cap (1000) exceeded for workout %s', _workout_id),
        'the row crossing the cap is refused'
    );

    RETURN NEXT lives_ok(
        format(
            'INSERT INTO workout_exercises (workout_id, exercise_id, exercise_order) VALUES (%L, %L, 0)',
            _other_id, _exercise_id
        ),
        'one workout at the cap does not block another'
    );
END
$$ LANGUAGE plpgsql;

SELECT * FROM runtests();

ROLLBACK;
