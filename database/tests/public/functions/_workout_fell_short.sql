BEGIN;

CREATE OR REPLACE FUNCTION test__workout_fell_short() RETURNS SETOF TEXT AS
$$
DECLARE
    _user TEXT := create_test_profile();
    _exercise UUID := create_test_exercise();
    _workout UUID := create_test_workout(_user_id => _user);
    _we UUID := create_test_workout_exercise(_workout_id => _workout, _exercise_id => _exercise);
    _set UUID := create_test_exercise_set(_workout_exercise_id => _we);
BEGIN
    RETURN NEXT has_function('public'::name, '_workout_fell_short'::name, ARRAY ['uuid']);
    UPDATE exercise_sets SET weight = 80, completed = true WHERE id = _set;

    RETURN NEXT ok(NOT _workout_fell_short(_workout), 'no plan, no comparison');

    INSERT INTO workout_plans (workout_id, plan)
    VALUES (_workout, jsonb_build_object('exercises', jsonb_build_array(jsonb_build_object(
        'sets', jsonb_build_array(jsonb_build_object('weight', 80, 'setId', _set))))));
    RETURN NEXT ok(NOT _workout_fell_short(_workout), 'following the plan is not falling short, lighter weeks included');

    UPDATE exercise_sets SET weight = 70 WHERE id = _set;
    RETURN NEXT ok(_workout_fell_short(_workout), 'lighter than planned');

    UPDATE exercise_sets SET weight = 90, completed = false WHERE id = _set;
    RETURN NEXT ok(_workout_fell_short(_workout), 'not completed');

    UPDATE exercise_sets SET completed = true WHERE id = _set;
    RETURN NEXT ok(NOT _workout_fell_short(_workout), 'heavier is fine');

    UPDATE workout_plans SET plan = jsonb_build_object('exercises', jsonb_build_array(jsonb_build_object(
        'sets', jsonb_build_array(jsonb_build_object('weight', 80))))) WHERE workout_id = _workout;
    RETURN NEXT ok(_workout_fell_short(_workout), 'a planned set that was never done');

    UPDATE workout_plans SET plan = '{"exercises": {"x": 1}}' WHERE workout_id = _workout;
    RETURN NEXT ok(NOT _workout_fell_short(_workout), 'a plan of the wrong shape compares as nothing');

    UPDATE workout_plans SET plan = '{"exercises": [1, {"sets": 2}, {"sets": [3]}]}' WHERE workout_id = _workout;
    RETURN NEXT ok(NOT _workout_fell_short(_workout), 'at any depth');

    UPDATE workout_plans SET plan = jsonb_build_object('exercises', jsonb_build_array(jsonb_build_object(
        'sets', jsonb_build_array(jsonb_build_object('weight', 'heavy', 'setId', _set))))) WHERE workout_id = _workout;
    RETURN NEXT ok(NOT _workout_fell_short(_workout), 'a weight that is no number compares as nothing');

    UPDATE workout_plans SET plan = jsonb_build_object('exercises', jsonb_build_array(jsonb_build_object(
        'sets', jsonb_build_array(jsonb_build_object('weight', 1e39, 'setId', _set))))) WHERE workout_id = _workout;
    RETURN NEXT ok(_workout_fell_short(_workout), 'a number past real''s range is still a number');
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test__summaries_follow_what_happens() RETURNS SETOF TEXT AS
$$
DECLARE
    _coach   TEXT := create_test_profile();
    _student TEXT := create_test_profile();
    _other   TEXT := create_test_profile();
    _id      UUID;
    _w       UUID;
BEGIN
    INSERT INTO connections (initiator_id, target_id, initiator_role, target_role, domain, status)
    VALUES (_other, _student, 'PEER', 'PEER', 'general', 'active');
    RETURN NEXT is((SELECT count(*) FROM client_summaries WHERE student_id = _student), 0::bigint, 'a peer has no summary');

    INSERT INTO connections (initiator_id, target_id, initiator_role, target_role, domain, status)
    VALUES (_coach, _student, 'COACH', 'STUDENT', 'fitness', 'active')
    RETURNING id INTO _id;
    RETURN NEXT is((SELECT dirty FROM client_summaries WHERE connection_id = _id), TRUE, 'a coach does, to be worked out');
    RETURN NEXT is((SELECT count(*) FROM push_digests WHERE user_id = _coach), 0::bigint, 'nothing owed yet');

    UPDATE client_summaries SET dirty = false WHERE connection_id = _id;
    _w := create_test_workout(_user_id => _student);
    RETURN NEXT is((SELECT dirty FROM client_summaries WHERE connection_id = _id), TRUE, 'a workout marks it');

    UPDATE workouts SET started_at = now(), completed_at = now() WHERE id = _w;
    RETURN NEXT is((SELECT count(*) FROM push_digests WHERE user_id = _coach), 1::bigint, 'finishing it owes a daily push');

    DELETE FROM push_digests WHERE user_id = _coach;
    UPDATE workouts SET name = 'a typo fixed', completed_at = completed_at WHERE id = _w;
    RETURN NEXT is((SELECT count(*) FROM push_digests WHERE user_id = _coach), 0::bigint, 'editing a finished one owes nothing');

    DELETE FROM push_digests WHERE user_id = _coach;
    UPDATE workouts SET hidden_at = now(), completed_at = completed_at + INTERVAL '1 minute' WHERE id = _w;
    RETURN NEXT is((SELECT count(*) FROM push_digests WHERE user_id = _coach), 0::bigint, 'a hidden one owes nothing');

    UPDATE client_summaries SET dirty = false WHERE connection_id = _id;
    UPDATE connections SET shares = '{goals}' WHERE id = _id;
    RETURN NEXT is((SELECT dirty FROM client_summaries WHERE connection_id = _id), TRUE, 'what is shared marks it');

    UPDATE client_summaries SET dirty = false WHERE connection_id = _id;
    INSERT INTO templates (user_id, name) VALUES (_student, 'a session');
    RETURN NEXT is((SELECT dirty FROM client_summaries WHERE connection_id = _id), TRUE, 'a session marks it');

    UPDATE client_summaries SET dirty = false WHERE connection_id = _id;
    DELETE FROM templates WHERE user_id = _student;
    RETURN NEXT is((SELECT dirty FROM client_summaries WHERE connection_id = _id), TRUE, 'and so does removing one');
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test__a_digest_is_owed_for_what_the_coach_reads() RETURNS SETOF TEXT AS
$$
DECLARE
    _coach   TEXT := create_test_profile();
    _student TEXT := create_test_profile();
BEGIN
    INSERT INTO connections (initiator_id, target_id, initiator_role, target_role, domain, status, accepted_at)
    VALUES (_coach, _student, 'COACH', 'STUDENT', 'fitness', 'active', now());

    INSERT INTO workouts (user_id, started_at, completed_at)
    VALUES (_student, now() - INTERVAL '1 year', now() - INTERVAL '1 year');
    RETURN NEXT is((SELECT count(*) FROM push_digests WHERE user_id = _coach), 0::bigint, 'not for one from before');

    INSERT INTO workouts (user_id, started_at, completed_at, logged_by)
    VALUES (_student, now(), now(), _coach);
    RETURN NEXT is((SELECT count(*) FROM push_digests WHERE user_id = _coach), 0::bigint, 'not for one they entered');

    INSERT INTO workouts (user_id, started_at, completed_at)
    VALUES (_student, now(), now()), (_student, now(), now());
    RETURN NEXT is((SELECT count(*) FROM push_digests WHERE user_id = _coach), 1::bigint, 'one for the client''s own');
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test__another_coach_starts_unreviewed() RETURNS SETOF TEXT AS
$$
DECLARE
    _a  TEXT := create_test_profile();
    _b  TEXT := create_test_profile();
    _id UUID;
BEGIN
    INSERT INTO connections (initiator_id, target_id, initiator_role, target_role, domain, status)
    VALUES (_a, _b, 'COACH', 'STUDENT', 'fitness', 'active')
    RETURNING id INTO _id;
    UPDATE client_summaries SET reviewed_at = now() WHERE connection_id = _id;

    UPDATE connections SET accepted_at = now() WHERE id = _id;
    RETURN NEXT isnt((SELECT reviewed_at FROM client_summaries WHERE connection_id = _id), NULL, 'the same coach keeps it');

    UPDATE connections SET initiator_id = _b, target_id = _a, accepted_at = now() WHERE id = _id;
    RETURN NEXT is((SELECT coach_id FROM client_summaries WHERE connection_id = _id), _b, 'the other way round');
    RETURN NEXT is((SELECT reviewed_at FROM client_summaries WHERE connection_id = _id), NULL, 'with nothing looked at');
END
$$ LANGUAGE plpgsql;

SELECT * FROM runtests();

ROLLBACK;
