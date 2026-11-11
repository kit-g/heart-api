BEGIN;

CREATE OR REPLACE FUNCTION test__bring_history_forward_signature() RETURNS SETOF TEXT AS
$$
BEGIN
    RETURN NEXT has_function('public'::name, '_bring_history_forward'::name, ARRAY ['text']);
    RETURN NEXT function_returns('public'::name, '_bring_history_forward'::name, ARRAY ['text'], 'integer');
    RETURN NEXT function_lang_is('public'::name, '_bring_history_forward'::name, ARRAY ['text'], 'plpgsql'::name);
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test__bring_history_forward_moves_whole_weeks() RETURNS SETOF TEXT AS
$$
DECLARE
    _user     TEXT := create_test_profile();
    _other    TEXT := create_test_profile();
    _start    TIMESTAMPTZ := date_trunc('day', now()) - INTERVAL '23 days' + INTERVAL '18 hours';
    _earlier  UUID;
    _latest   UUID;
    _theirs   UUID;
    _set      UUID;
    _goal     UUID;
BEGIN
    RETURN NEXT is((SELECT count(*) FROM workouts WHERE user_id IN (_user, _other)), 0::bigint, 'no workouts yet');
    RETURN NEXT is((SELECT count(*) FROM skips WHERE user_id = _user), 0::bigint, 'no skips yet');
    RETURN NEXT is((SELECT count(*) FROM goals WHERE user_id = _user), 0::bigint, 'no goals yet');

    _earlier := create_test_workout(_user_id => _user);
    _latest := create_test_workout(_user_id => _user);
    _theirs := create_test_workout(_user_id => _other);

    UPDATE workouts
    SET started_at = _start - INTERVAL '7 days',
        completed_at = _start - INTERVAL '7 days' + INTERVAL '1 hour'
    WHERE id IN (_earlier, _theirs);

    UPDATE workouts
    SET started_at = _start,
        completed_at = _start + INTERVAL '1 hour',
        pauses = jsonb_build_array(
            jsonb_build_object('start', _start + INTERVAL '10 minutes', 'end', _start + INTERVAL '15 minutes')
        )
    WHERE id = _latest;

    _set := create_test_exercise_set(
        _workout_exercise_id => create_test_workout_exercise(_latest, create_test_exercise()),
        _completed => true
    );
    UPDATE exercise_sets SET completed_at = _start + INTERVAL '5 minutes' WHERE id = _set;

    INSERT INTO skips (user_id, at) VALUES (_user, _start - INTERVAL '2 days');

    INSERT INTO goals (user_id, metric, stages)
    VALUES (
        _user,
        'workouts',
        jsonb_build_array(
            jsonb_build_object('id', 'a', 'target', 10, 'dueOn', to_char(_start, 'YYYY-MM-DD'), 'achievedAt', _start),
            jsonb_build_object('id', 'b', 'target', 20)
        )
    )
    RETURNING id INTO _goal;

    RETURN NEXT is(_bring_history_forward(_user), 3, '23 days back moves three weeks');

    RETURN NEXT is(
        (SELECT started_at FROM workouts WHERE id = _latest),
        _start + INTERVAL '21 days',
        'the latest workout lands within the past week, on its weekday'
    );
    RETURN NEXT is(
        (SELECT started_at FROM workouts WHERE id = _earlier),
        _start + INTERVAL '14 days',
        'the history keeps its spacing'
    );
    RETURN NEXT is(
        (SELECT (pauses -> 0 ->> 'start')::timestamptz FROM workouts WHERE id = _latest),
        _start + INTERVAL '21 days' + INTERVAL '10 minutes',
        'pauses move with their workout'
    );
    RETURN NEXT is(
        (SELECT completed_at FROM exercise_sets WHERE id = _set),
        _start + INTERVAL '21 days' + INTERVAL '5 minutes',
        'sets move with their workout'
    );
    RETURN NEXT is(
        (SELECT at FROM skips WHERE user_id = _user),
        _start + INTERVAL '19 days',
        'skips move'
    );
    RETURN NEXT is(
        (SELECT stages FROM goals WHERE id = _goal),
        jsonb_build_array(
            jsonb_build_object(
                'id', 'a',
                'target', 10,
                'dueOn', to_char(_start + INTERVAL '21 days', 'YYYY-MM-DD'),
                'achievedAt', _start + INTERVAL '21 days'
            ),
            jsonb_build_object('id', 'b', 'target', 20)
        ),
        'goal dates move, and a stage without them is left as it was'
    );
    RETURN NEXT is(
        (SELECT started_at FROM workouts WHERE id = _theirs),
        _start - INTERVAL '7 days',
        'another account is untouched'
    );

    RETURN NEXT is(_bring_history_forward(_user), 0, 'a current history stays put');
    RETURN NEXT is(_bring_history_forward(create_test_profile()), 0, 'an empty history stays put');
END
$$ LANGUAGE plpgsql;

SELECT * FROM runtests();

ROLLBACK;
