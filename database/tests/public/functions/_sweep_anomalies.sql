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

CREATE OR REPLACE FUNCTION test__sweep_anomalies_one_failure_is_one_user() RETURNS SETOF TEXT AS
$$
DECLARE
    _bad      TEXT := create_test_profile();
    _good     TEXT := create_test_profile();
    _broken   UUID := create_test_workout(_bad);
    _running  UUID := create_test_workout(_good);
BEGIN
    UPDATE workouts
    SET started_at = now() - interval '9 hours', completed_at = now()
    WHERE id IN (_broken, _running);
    CREATE FUNCTION pg_temp._fail_for() RETURNS TRIGGER AS
    $f$
    BEGIN
        IF NEW.user_id = current_setting('test.bad_user') THEN
            RAISE EXCEPTION 'judging this one fails';
        END IF;
        RETURN NEW;
    END
    $f$ LANGUAGE plpgsql;
    PERFORM set_config('test.bad_user', _bad, true);
    CREATE TRIGGER _fail BEFORE INSERT ON anomalies FOR EACH ROW EXECUTE FUNCTION pg_temp._fail_for();

    DELETE FROM anomaly_sweeps;
    PERFORM _sweep_anomalies();
    RETURN NEXT is(
            (SELECT count(*) FROM anomalies WHERE workout_id = _running),
            1::bigint,
            'a user whose log fails to judge leaves everyone else''s judged'
                );
    RETURN NEXT is((SELECT count(*) FROM anomaly_sweeps), 1::bigint, 'and the sweep still moves on');

    DROP TRIGGER _fail ON anomalies;
END
$$ LANGUAGE plpgsql;

SELECT * FROM runtests();

ROLLBACK;
