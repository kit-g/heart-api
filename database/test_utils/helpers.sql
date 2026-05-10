-- Test helpers for the Heart database. Loaded once per psql session before
-- pg_prove runs. Defines:
--   create_test_*()       — minimal-arg builders that return ids/uuids
--   validate_format_*()   — SETOF BOOL JSON shape assertions

-- ---------- builders ----------

CREATE OR REPLACE FUNCTION create_test_profile(_id TEXT DEFAULT NULL) RETURNS TEXT AS
$$
DECLARE
    _new_id TEXT;
BEGIN
    INSERT INTO profiles (id, username, email)
    VALUES (
        coalesce(_id, 'test-' || gen_random_uuid()::text),
        'test_' || gen_random_uuid()::text,
        gen_random_uuid()::text || '@test.local'
    )
    ON CONFLICT (id) DO NOTHING
    RETURNING id INTO _new_id;
    RETURN coalesce(_new_id, _id);
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION create_test_exercise(
    _name TEXT DEFAULT NULL,
    _category TEXT DEFAULT 'Barbell',
    _target TEXT DEFAULT 'Chest',
    _user_id TEXT DEFAULT NULL
) RETURNS UUID AS
$$
DECLARE
    _new_id UUID;
BEGIN
    INSERT INTO exercises (name, category, target, user_id)
    VALUES (
        coalesce(_name, 'Test Exercise ' || gen_random_uuid()::text),
        _category,
        _target,
        _user_id
    )
    RETURNING id INTO _new_id;
    RETURN _new_id;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION create_test_workout(
    _user_id TEXT DEFAULT NULL,
    _name TEXT DEFAULT NULL
) RETURNS UUID AS
$$
DECLARE
    _new_id UUID;
BEGIN
    INSERT INTO workouts (user_id, name)
    VALUES (
        coalesce(_user_id, create_test_profile()),
        _name
    )
    RETURNING id INTO _new_id;
    RETURN _new_id;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION create_test_workout_exercise(
    _workout_id UUID,
    _exercise_id UUID,
    _exercise_order INT DEFAULT 0
) RETURNS UUID AS
$$
DECLARE
    _new_id UUID;
BEGIN
    INSERT INTO workout_exercises (workout_id, exercise_id, exercise_order)
    VALUES (_workout_id, _exercise_id, _exercise_order)
    RETURNING id INTO _new_id;
    RETURN _new_id;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION create_test_exercise_set(
    _workout_exercise_id UUID,
    _set_order INT DEFAULT 0,
    _weight REAL DEFAULT NULL,
    _reps INT DEFAULT NULL,
    _duration INT DEFAULT NULL,
    _distance REAL DEFAULT NULL,
    _completed BOOLEAN DEFAULT FALSE
) RETURNS UUID AS
$$
DECLARE
    _new_id UUID;
BEGIN
    INSERT INTO exercise_sets (
        workout_exercise_id, set_order, weight, reps, duration, distance, completed
    )
    VALUES (_workout_exercise_id, _set_order, _weight, _reps, _duration, _distance, _completed)
    RETURNING id INTO _new_id;
    RETURN _new_id;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION create_test_template(
    _user_id TEXT DEFAULT NULL,
    _name TEXT DEFAULT NULL,
    _order_index INT DEFAULT 0
) RETURNS UUID AS
$$
DECLARE
    _new_id UUID;
BEGIN
    INSERT INTO templates (user_id, name, order_index)
    VALUES (
        coalesce(_user_id, create_test_profile()),
        coalesce(_name, 'Test Template'),
        _order_index
    )
    RETURNING id INTO _new_id;
    RETURN _new_id;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION create_test_template_exercise(
    _template_id UUID,
    _exercise_id UUID,
    _exercise_order INT DEFAULT 0
) RETURNS UUID AS
$$
DECLARE
    _new_id UUID;
BEGIN
    INSERT INTO template_exercises (template_id, exercise_id, exercise_order)
    VALUES (_template_id, _exercise_id, _exercise_order)
    RETURNING id INTO _new_id;
    RETURN _new_id;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION create_test_template_set(
    _template_exercise_id UUID,
    _set_order INT DEFAULT 0,
    _weight REAL DEFAULT NULL,
    _reps INT DEFAULT NULL,
    _duration INT DEFAULT NULL,
    _distance REAL DEFAULT NULL
) RETURNS UUID AS
$$
DECLARE
    _new_id UUID;
BEGIN
    INSERT INTO template_exercise_sets (
        template_exercise_id, set_order, weight, reps, duration, distance
    )
    VALUES (_template_exercise_id, _set_order, _weight, _reps, _duration, _distance)
    RETURNING id INTO _new_id;
    RETURN _new_id;
END
$$ LANGUAGE plpgsql;

-- ---------- JSON shape validators ----------

CREATE OR REPLACE FUNCTION validate_format_exercise_set(_set JSONB) RETURNS SETOF BOOL AS
$$
BEGIN
    RETURN NEXT (SELECT count(*) FROM jsonb_object_keys(_set)) = 8;
    RETURN NEXT jsonb_typeof(_set -> 'id') = 'string';
    RETURN NEXT jsonb_typeof(_set -> 'weight') = 'number' OR jsonb_typeof(_set -> 'weight') = 'null';
    RETURN NEXT jsonb_typeof(_set -> 'reps') = 'number' OR jsonb_typeof(_set -> 'reps') = 'null';
    RETURN NEXT jsonb_typeof(_set -> 'duration') = 'number' OR jsonb_typeof(_set -> 'duration') = 'null';
    RETURN NEXT jsonb_typeof(_set -> 'distance') = 'number' OR jsonb_typeof(_set -> 'distance') = 'null';
    RETURN NEXT jsonb_typeof(_set -> 'completed') = 'boolean';
    RETURN NEXT jsonb_typeof(_set -> 'started_at') = 'string' OR jsonb_typeof(_set -> 'started_at') = 'null';
    RETURN NEXT jsonb_typeof(_set -> 'set_order') = 'number';
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION validate_format_template_set(_set JSONB) RETURNS SETOF BOOL AS
$$
BEGIN
    RETURN NEXT (SELECT count(*) FROM jsonb_object_keys(_set)) = 6;
    RETURN NEXT jsonb_typeof(_set -> 'id') = 'string';
    RETURN NEXT jsonb_typeof(_set -> 'weight') = 'number' OR jsonb_typeof(_set -> 'weight') = 'null';
    RETURN NEXT jsonb_typeof(_set -> 'reps') = 'number' OR jsonb_typeof(_set -> 'reps') = 'null';
    RETURN NEXT jsonb_typeof(_set -> 'duration') = 'number' OR jsonb_typeof(_set -> 'duration') = 'null';
    RETURN NEXT jsonb_typeof(_set -> 'distance') = 'number' OR jsonb_typeof(_set -> 'distance') = 'null';
    RETURN NEXT jsonb_typeof(_set -> 'set_order') = 'number';
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION validate_format_workout_exercise(_we JSONB) RETURNS SETOF BOOL AS
$$
BEGIN
    RETURN NEXT (SELECT count(*) FROM jsonb_object_keys(_we)) = 4;
    RETURN NEXT jsonb_typeof(_we -> 'id') = 'string';
    RETURN NEXT jsonb_typeof(_we -> 'exercise') = 'object';
    RETURN NEXT (SELECT count(*) FROM jsonb_object_keys(_we -> 'exercise')) = 4;
    RETURN NEXT jsonb_typeof(_we -> 'exercise' -> 'id') = 'string';
    RETURN NEXT jsonb_typeof(_we -> 'exercise' -> 'name') = 'string';
    RETURN NEXT jsonb_typeof(_we -> 'exercise' -> 'category') = 'string';
    RETURN NEXT jsonb_typeof(_we -> 'exercise' -> 'target') = 'string';
    RETURN NEXT jsonb_typeof(_we -> 'exercise_order') = 'number';
    RETURN NEXT jsonb_typeof(_we -> 'sets') = 'array';
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION validate_format_template_exercise(_te JSONB) RETURNS SETOF BOOL AS
$$
BEGIN
    RETURN NEXT (SELECT count(*) FROM jsonb_object_keys(_te)) = 4;
    RETURN NEXT jsonb_typeof(_te -> 'id') = 'string';
    RETURN NEXT jsonb_typeof(_te -> 'exercise') = 'object';
    RETURN NEXT (SELECT count(*) FROM jsonb_object_keys(_te -> 'exercise')) = 4;
    RETURN NEXT jsonb_typeof(_te -> 'exercise' -> 'id') = 'string';
    RETURN NEXT jsonb_typeof(_te -> 'exercise' -> 'name') = 'string';
    RETURN NEXT jsonb_typeof(_te -> 'exercise' -> 'category') = 'string';
    RETURN NEXT jsonb_typeof(_te -> 'exercise' -> 'target') = 'string';
    RETURN NEXT jsonb_typeof(_te -> 'exercise_order') = 'number';
    RETURN NEXT jsonb_typeof(_te -> 'sets') = 'array';
END
$$ LANGUAGE plpgsql;
