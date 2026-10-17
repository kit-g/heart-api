BEGIN;

CREATE OR REPLACE FUNCTION test__sweep_anomalies_signature() RETURNS SETOF TEXT AS
$$
BEGIN
    RETURN NEXT has_function('public'::name, '_sweep_anomalies'::name);
    RETURN NEXT function_returns('public'::name, '_sweep_anomalies'::name, 'integer');
    RETURN NEXT function_lang_is('public'::name, '_sweep_anomalies'::name, 'plpgsql'::name);
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test__sweep_anomalies_reads_who_wrote_since() RETURNS SETOF TEXT AS
$$
DECLARE
    _user    TEXT := create_test_profile();
    _workout UUID := create_test_workout(_user);
BEGIN
    UPDATE workouts
    SET started_at = now() - interval '9 hours', completed_at = now()
    WHERE id = _workout;

    DELETE FROM anomaly_sweeps;
    RETURN NEXT ok(_sweep_anomalies() >= 1, 'the first sweep reads everyone');
    RETURN NEXT is(
            (SELECT reason FROM anomalies WHERE workout_id = _workout),
            'duration_left_running',
            'and finds what is there'
                );
    RETURN NEXT is((SELECT count(*) FROM anomaly_sweeps), 1::bigint, 'it remembers when it ran');

    UPDATE anomaly_sweeps SET swept_at = now() + interval '1 hour';
    RETURN NEXT is(_sweep_anomalies(), 0, 'no one wrote since the last sweep');
END
$$ LANGUAGE plpgsql;

SELECT * FROM runtests();

ROLLBACK;
