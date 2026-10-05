BEGIN;

CREATE OR REPLACE FUNCTION test__archive_workout_signature() RETURNS SETOF TEXT AS
$$
BEGIN
    RETURN NEXT has_function('public'::name, '_archive_workout'::name);
    RETURN NEXT function_lang_is('public'::name, '_archive_workout'::name, 'plpgsql'::name);
    RETURN NEXT function_returns('public'::name, '_archive_workout'::name, 'trigger');
    RETURN NEXT trigger_is(
            'public'::name, 'workouts'::name,
            'archive_workout_before_delete'::name,
            'public'::name, '_archive_workout'::name
        );
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test__archive_workout_copies_row_on_delete() RETURNS SETOF TEXT AS
$$
DECLARE
    _user_id TEXT;
    _w_id    UUID;
BEGIN
    _user_id := create_test_profile();
    _w_id    := create_test_workout(_user_id => _user_id, _name => 'archive me');
    UPDATE workouts
    SET calories = 420,
        note = 'felt strong',
        pauses = '[{"start": "2026-10-03T18:10:00Z", "end": "2026-10-03T18:20:00Z"}]'
    WHERE id = _w_id;

    DELETE FROM workouts WHERE id = _w_id;

    RETURN NEXT is(
            (SELECT count(*) FROM archive.deleted_workouts WHERE id = _w_id),
            1::bigint,
            'archive row written'
        );
    RETURN NEXT is(
            (SELECT user_id FROM archive.deleted_workouts WHERE id = _w_id),
            _user_id,
            'archive preserved user_id'
        );
    RETURN NEXT is(
            (SELECT name FROM archive.deleted_workouts WHERE id = _w_id),
            'archive me',
            'archive preserved name'
        );
    RETURN NEXT is(
            (SELECT calories FROM archive.deleted_workouts WHERE id = _w_id),
            420::real,
            'archive preserved calories'
        );
    RETURN NEXT is(
            (SELECT note FROM archive.deleted_workouts WHERE id = _w_id),
            'felt strong',
            'archive preserved the workout note'
        );
    RETURN NEXT is(
            (SELECT jsonb_array_length(pauses) FROM archive.deleted_workouts WHERE id = _w_id),
            1,
            'archive preserved the pauses'
        );
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test__archive_workout_snapshots_exercises_jsonb() RETURNS SETOF TEXT AS
$$
DECLARE
    _user_id TEXT;
    _ex_id   UUID;
    _w_id    UUID;
    _we_id   UUID;
    _archived JSONB;
BEGIN
    _user_id := create_test_profile();
    _ex_id   := create_test_exercise('Bench Press', 'Barbell', 'Chest', _user_id);
    _w_id    := create_test_workout(_user_id => _user_id);
    _we_id   := create_test_workout_exercise(_w_id, _ex_id, 0);
    PERFORM create_test_exercise_set(_we_id, 0, 135, 5);
    UPDATE exercise_sets SET set_type = 'w', rpe = 6.5 WHERE workout_exercise_id = _we_id;

    DELETE FROM workouts WHERE id = _w_id;

    SELECT exercises INTO _archived FROM archive.deleted_workouts WHERE id = _w_id;

    RETURN NEXT is(jsonb_array_length(_archived), 1, 'archived exercises array has the entry');
    RETURN NEXT is(_archived -> 0 -> 'exercise' ->> 'name', 'Bench Press', 'exercise name in snapshot');
    RETURN NEXT is(jsonb_array_length(_archived -> 0 -> 'sets'), 1, 'sets in snapshot');
    RETURN NEXT is(_archived -> 0 -> 'sets' -> 0 ->> 'set_type', 'warmup', 'set type in snapshot');
    RETURN NEXT is((_archived -> 0 -> 'sets' -> 0 ->> 'rpe')::numeric, 6.5, 'rpe in snapshot');
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test__archive_workout_sets_deleted_at() RETURNS SETOF TEXT AS
$$
DECLARE
    _user_id TEXT;
    _w_id    UUID;
    _before  TIMESTAMPTZ;
    _row     RECORD;
BEGIN
    _user_id := create_test_profile();
    _w_id    := create_test_workout(_user_id => _user_id);

    _before := now();
    DELETE FROM workouts WHERE id = _w_id;

    SELECT deleted_at INTO _row FROM archive.deleted_workouts WHERE id = _w_id;

    RETURN NEXT ok(_row.deleted_at IS NOT NULL, 'deleted_at populated');
    RETURN NEXT ok(_row.deleted_at >= _before, 'deleted_at >= moment before delete');
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test__archive_workout_redelete_replaces_snapshot() RETURNS SETOF TEXT AS
$$
DECLARE
    _user_id TEXT;
    _w_id    UUID;
BEGIN
    _user_id := create_test_profile();
    _w_id := create_test_workout(_user_id => _user_id, _name => 'first life');
    RETURN NEXT is((SELECT count(*) FROM archive.deleted_workouts WHERE id = _w_id), 0::bigint, 'not archived yet');

    DELETE FROM workouts WHERE id = _w_id;
    INSERT INTO workouts (id, user_id, name, started_at) VALUES (_w_id, _user_id, 'second life', now());
    DELETE FROM workouts WHERE id = _w_id;

    RETURN NEXT is((SELECT count(*) FROM archive.deleted_workouts WHERE id = _w_id), 1::bigint, 'one snapshot per id');
    RETURN NEXT is((SELECT name FROM archive.deleted_workouts WHERE id = _w_id), 'second life', 'the newer snapshot wins');
END
$$ LANGUAGE plpgsql;

SELECT * FROM runtests();

ROLLBACK;
