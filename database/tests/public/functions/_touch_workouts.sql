BEGIN;

-- now() is fixed for the whole transaction, so every case backdates
-- updated_at first and then checks the change moved it to now(). Each
-- backdate is to a new value: writing the value a column already holds is
-- indistinguishable from not writing it, and the trigger then stamps now().

CREATE OR REPLACE FUNCTION test__touch_workouts_signatures() RETURNS SETOF TEXT AS
$$
BEGIN
    RETURN NEXT has_function('public'::name, '_touch_workout'::name);
    RETURN NEXT function_returns('public'::name, '_touch_workout'::name, 'trigger');
    RETURN NEXT function_lang_is('public'::name, '_touch_workout'::name, 'plpgsql'::name);
    RETURN NEXT has_function('public'::name, '_touch_workouts_of_children'::name);
    RETURN NEXT has_function('public'::name, '_touch_workouts_of_sets'::name);
    RETURN NEXT has_trigger('public'::name, 'workouts'::name, 'workouts_touch'::name);
    RETURN NEXT has_trigger('public'::name, 'exercise_sets'::name, 'exercise_sets_touch_update'::name);
    RETURN NEXT has_trigger('public'::name, 'workout_images'::name, 'workout_images_touch_insert'::name);
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test__touch_workouts_follows_every_part() RETURNS SETOF TEXT AS
$$
DECLARE
    _user_id     TEXT;
    _exercise_id UUID;
    _w_id        UUID;
    _other_id    UUID;
    _we_id       UUID;
    _set_id      UUID;
    _old         TIMESTAMPTZ := '2020-01-01T00:00:00Z';
BEGIN
    _user_id := create_test_profile();
    RETURN NEXT is((SELECT count(*) FROM workouts WHERE user_id = _user_id), 0::bigint, 'no workouts yet');

    _exercise_id := create_test_exercise(_user_id => _user_id);
    _w_id := create_test_workout(_user_id => _user_id, _name => 'touched');
    _other_id := create_test_workout(_user_id => _user_id, _name => 'untouched');
    _we_id := create_test_workout_exercise(_workout_id => _w_id, _exercise_id => _exercise_id);

    RETURN NEXT ok((SELECT updated_at FROM workouts WHERE id = _w_id) IS NOT NULL, 'a new workout has updated_at');
    UPDATE workouts SET updated_at = _old WHERE id = _other_id;

    UPDATE workouts SET updated_at = _old - interval '1 day' WHERE id = _w_id;
    UPDATE workouts SET name = 'renamed' WHERE id = _w_id;
    RETURN NEXT is((SELECT updated_at FROM workouts WHERE id = _w_id), now(), 'editing the row bumps it');

    UPDATE workouts SET updated_at = _old - interval '2 day' WHERE id = _w_id;
    _set_id := create_test_exercise_set(_workout_exercise_id => _we_id, _weight => 80, _reps => 5);
    RETURN NEXT is((SELECT updated_at FROM workouts WHERE id = _w_id), now(), 'adding a set bumps its workout');
    RETURN NEXT is((SELECT updated_at FROM workouts WHERE id = _other_id), _old, 'and only its workout');

    UPDATE workouts SET updated_at = _old - interval '3 day' WHERE id = _w_id;
    UPDATE exercise_sets SET reps = 6 WHERE id = _set_id;
    RETURN NEXT is((SELECT updated_at FROM workouts WHERE id = _w_id), now(), 'editing a set bumps it');

    UPDATE workouts SET updated_at = _old - interval '4 day' WHERE id = _w_id;
    DELETE FROM exercise_sets WHERE id = _set_id;
    RETURN NEXT is((SELECT updated_at FROM workouts WHERE id = _w_id), now(), 'removing a set bumps it');

    UPDATE workouts SET updated_at = _old - interval '5 day' WHERE id = _w_id;
    UPDATE workout_exercises SET note = 'grip' WHERE id = _we_id;
    RETURN NEXT is((SELECT updated_at FROM workouts WHERE id = _w_id), now(), 'editing an exercise bumps it');

    UPDATE workouts SET updated_at = _old - interval '6 day' WHERE id = _w_id;
    INSERT INTO workout_images (workout_id, user_id, key) VALUES (_w_id, _user_id, 'k/' || _w_id);
    RETURN NEXT is((SELECT updated_at FROM workouts WHERE id = _w_id), now(), 'adding an image bumps it');

    DELETE FROM workouts WHERE id = _w_id;
    RETURN NEXT is((SELECT count(*) FROM workouts WHERE id = _w_id), 0::bigint, 'deleting the workout still cascades cleanly');
END
$$ LANGUAGE plpgsql;

SELECT * FROM runtests();

ROLLBACK;
