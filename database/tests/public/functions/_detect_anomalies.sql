-- One user's log judged against the anomaly rules: what each rule flags, what
-- it leaves alone, and that a decision holds until the entry changes.

BEGIN;

CREATE OR REPLACE FUNCTION test__detect_anomalies_signature() RETURNS SETOF TEXT AS
$$
BEGIN
    RETURN NEXT has_function('public'::name, '_detect_anomalies'::name, ARRAY ['text']);
    RETURN NEXT function_returns('public'::name, '_detect_anomalies'::name, ARRAY ['text'], 'integer');
    RETURN NEXT function_lang_is('public'::name, '_detect_anomalies'::name, ARRAY ['text'], 'sql'::name);
END
$$ LANGUAGE plpgsql;

-- A workout of one exercise, one completed set per weight/reps pair, started
-- [days] after 2026-01-01 and lasting [minutes].
CREATE OR REPLACE FUNCTION _anomaly_session(
    _user_id TEXT,
    _exercise_id UUID,
    _days INT,
    _sets REAL[][],
    _minutes INT DEFAULT 60
) RETURNS UUID AS
$$
DECLARE
    _workout UUID := create_test_workout(_user_id);
    _we      UUID := create_test_workout_exercise(_workout, _exercise_id);
    _start   TIMESTAMPTZ := timestamptz '2026-01-01T10:00:00Z' + make_interval(days => _days);
BEGIN
    UPDATE workouts
    SET started_at = _start, completed_at = _start + make_interval(mins => _minutes)
    WHERE id = _workout;
    FOR i IN 1..array_length(_sets, 1)
        LOOP
            PERFORM create_test_exercise_set(_we, i - 1, _sets[i][1], _sets[i][2]::int, NULL, NULL, true);
        END LOOP;
    RETURN _workout;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION _anomaly_set(_workout UUID, _weight REAL) RETURNS UUID AS
$$
SELECT s.id
FROM exercise_sets s
JOIN workout_exercises we ON we.id = s.workout_exercise_id
WHERE we.workout_id = _workout AND s.weight = _weight
$$ LANGUAGE sql;

CREATE OR REPLACE FUNCTION test__detect_anomalies_flags_by_rule() RETURNS SETOF TEXT AS
$$
DECLARE
    _user  TEXT := create_test_profile();
    _bench UUID := create_test_exercise(NULL, 'Barbell', 'Chest', _user);
    _odd   UUID;
    _long  UUID;
    _paused UUID;
BEGIN
    RETURN NEXT is(_detect_anomalies(_user), 0, 'an empty log has nothing to find');

    FOR d IN 1..8
        LOOP
            PERFORM _anomaly_session(_user, _bench, d, ARRAY [[100, 5]]::real[][]);
        END LOOP;
    _odd := _anomaly_session(
            _user, _bench, 20,
            ARRAY [[630, 5], [12, 150], [90.5, 150], [110, 8]]::real[][]
            );
    _long := _anomaly_session(_user, _bench, 21, ARRAY [[100, 5]]::real[][], 8 * 60);
    _paused := _anomaly_session(_user, _bench, 22, ARRAY [[100, 5]]::real[][], 7 * 60);
    UPDATE workouts
    SET pauses = jsonb_build_array(jsonb_build_object(
            'start', started_at + interval '1 hour',
            'end', started_at + interval '3 hours'
                                   ))
    WHERE id = _paused;

    RETURN NEXT is(_detect_anomalies(_user), 4, 'four entries are suspicious');
    RETURN NEXT is(
            (SELECT reason FROM anomalies WHERE set_id = _anomaly_set(_odd, 630)),
            'outlier_weight',
            'a weight far over the exercise''s median'
                );
    RETURN NEXT is(
            (SELECT typical FROM anomalies WHERE set_id = _anomaly_set(_odd, 630)),
            100::real,
            'judged against that median'
                );
    RETURN NEXT is(
            (SELECT reason FROM anomalies WHERE set_id = _anomaly_set(_odd, 12)),
            'swap_suspected',
            '12 kg for 150 reads as 150 kg for 12'
                );
    RETURN NEXT is(
            (SELECT reason FROM anomalies WHERE set_id = _anomaly_set(_odd, 90.5)),
            'implausible_reps',
            '150 reps of a loaded set that no swap explains'
                );
    RETURN NEXT is(
            (SELECT count(*) FROM anomalies WHERE set_id = _anomaly_set(_odd, 110)),
            0::bigint,
            'a set in line is left alone'
                );
    RETURN NEXT is(
            (SELECT observed FROM anomalies WHERE workout_id = _long AND set_id IS NULL),
            '{"seconds": 28800}'::jsonb,
            'a workout left running for 8 hours'
                );
    RETURN NEXT is(
            (SELECT count(*) FROM anomalies WHERE workout_id = _paused AND set_id IS NULL),
            0::bigint,
            'seven hours less two paused is not'
                );
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test__detect_anomalies_waits_for_a_baseline() RETURNS SETOF TEXT AS
$$
DECLARE
    _user  TEXT := create_test_profile();
    _press UUID := create_test_exercise(NULL, 'Barbell', 'Shoulders', _user);
BEGIN
    FOR d IN 1..6
        LOOP
            PERFORM _anomaly_session(_user, _press, d, ARRAY [[50, 5]]::real[][]);
        END LOOP;
    PERFORM _anomaly_session(_user, _press, 10, ARRAY [[300, 5]]::real[][]);
    RETURN NEXT is(_detect_anomalies(_user), 0, 'seven sets are too few to call one an outlier');
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test__detect_anomalies_keeps_decisions() RETURNS SETOF TEXT AS
$$
DECLARE
    _user  TEXT := create_test_profile();
    _squat UUID := create_test_exercise(NULL, 'Barbell', 'Legs', _user);
    _odd   UUID;
    _heavy UUID;
    _light UUID;
BEGIN
    FOR d IN 1..8
        LOOP
            PERFORM _anomaly_session(_user, _squat, d, ARRAY [[140, 5]]::real[][]);
        END LOOP;
    _odd := _anomaly_session(_user, _squat, 20, ARRAY [[630, 5], [700, 3]]::real[][]);
    _heavy := _anomaly_set(_odd, 630);
    _light := _anomaly_set(_odd, 700);
    PERFORM _detect_anomalies(_user);

    UPDATE anomalies SET status = 'invalid', resolved_at = now() WHERE set_id = _heavy;
    UPDATE anomalies SET status = 'valid', resolved_at = now() WHERE set_id = _light;
    PERFORM _detect_anomalies(_user);
    RETURN NEXT is(
            (SELECT status FROM anomalies WHERE set_id = _heavy),
            'invalid',
            'a decision holds while the entry is unchanged'
                );

    UPDATE exercise_sets SET weight = 143 WHERE id = _heavy;
    UPDATE exercise_sets SET weight = 650 WHERE id = _light;
    PERFORM _detect_anomalies(_user);
    RETURN NEXT is(
            (SELECT count(*) FROM anomalies WHERE set_id = _heavy),
            0::bigint,
            'an entry fixed is no longer suspicious'
                );
    RETURN NEXT is(
            (SELECT status FROM anomalies WHERE set_id = _light),
            'pending',
            'an entry edited and still odd is asked about again'
                );
END
$$ LANGUAGE plpgsql;

SELECT * FROM runtests();

ROLLBACK;
