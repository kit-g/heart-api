-- One user's history moved from one exercise to another: every row of theirs
-- keyed on the source is re-keyed on the target, a custom source is deleted, a
-- library source kept, a preference on both sides resolves to the target's, and
-- a dry run reports the same counts without writing.

BEGIN;

CREATE OR REPLACE FUNCTION test__move_exercise_history_signature() RETURNS SETOF TEXT AS
$$
BEGIN
    RETURN NEXT has_function('public'::name, '_move_exercise_history'::name, ARRAY ['text', 'uuid', 'uuid', 'boolean']);
    RETURN NEXT function_returns('public'::name, '_move_exercise_history'::name, ARRAY ['text', 'uuid', 'uuid', 'boolean'], 'setof record');
    RETURN NEXT function_lang_is('public'::name, '_move_exercise_history'::name, ARRAY ['text', 'uuid', 'uuid', 'boolean'], 'plpgsql'::name);
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test__move_exercise_history_rekeys_and_deletes_the_custom() RETURNS SETOF TEXT AS
$$
DECLARE
    _user_id   TEXT;
    _source_id UUID;
    _target_id UUID;
    _w1        UUID;
    _w2        UUID;
    _we        UUID;
    _t         UUID;
    _r         RECORD;
BEGIN
    _user_id   := create_test_profile();
    _source_id := create_test_exercise('Brzuszki', 'Reps Only', 'Core', _user_id);
    _target_id := create_test_exercise(_category => 'Reps Only', _target => 'Core');

    RETURN NEXT is((SELECT count(*) FROM workouts WHERE user_id = _user_id), 0::bigint, 'no workouts yet');
    RETURN NEXT is((SELECT count(*) FROM templates WHERE user_id = _user_id), 0::bigint, 'no templates yet');
    RETURN NEXT is((SELECT count(*) FROM goals WHERE user_id = _user_id), 0::bigint, 'no goals yet');
    RETURN NEXT is((SELECT count(*) FROM exercise_preferences WHERE user_id = _user_id), 0::bigint, 'no preferences yet');

    _w1 := create_test_workout(_user_id => _user_id, _name => 'one');
    _we := create_test_workout_exercise(_w1, _source_id, 0);
    PERFORM create_test_exercise_set(_we, 0, NULL, 12);
    PERFORM create_test_workout_exercise(_w1, _target_id, 1);
    _w2 := create_test_workout(_user_id => _user_id, _name => 'two');
    PERFORM create_test_workout_exercise(_w2, _source_id, 0);
    _t := create_test_template(_user_id => _user_id, _name => 'core day');
    PERFORM create_test_template_exercise(_t, _source_id, 0);
    INSERT INTO exercise_preferences (user_id, exercise_id, chart_type, rest_timer)
    VALUES (_user_id, _source_id, 'totalReps', 60);
    INSERT INTO goals (user_id, metric, exercise_id, stages)
    VALUES (_user_id, 'totalReps', _source_id, '[{"id": "s1", "target": 100}]'),
           (_user_id, 'maxConsecutiveReps', _source_id, '[{"id": "s1", "target": 30}]');
    -- as an earlier transaction would have left them
    UPDATE workouts SET changed_xid = '1'::xid8 WHERE id IN (_w1, _w2);

    SELECT * INTO _r FROM _move_exercise_history(_user_id, _source_id, _target_id);

    RETURN NEXT is(_r.workout_exercises_moved, 2, 'two workout exercises moved');
    RETURN NEXT is(_r.template_exercises_moved, 1, 'one template exercise moved');
    RETURN NEXT is(_r.preferences_moved, 1, 'the preference moved');
    RETURN NEXT is(_r.preferences_dropped, 0, 'nothing stood in its way');
    RETURN NEXT is(_r.chart_preferences_moved, 1, 'it carried a chart setting');
    RETURN NEXT is(_r.goals_moved, 2, 'both goals moved');
    RETURN NEXT ok(_r.source_deleted, 'the custom source was deleted');

    RETURN NEXT is((SELECT count(*) FROM exercises WHERE id = _source_id), 0::bigint, 'the custom row is gone');
    RETURN NEXT is(
        (SELECT count(*) FROM workout_exercises we JOIN workouts w ON w.id = we.workout_id WHERE w.user_id = _user_id AND we.exercise_id = _target_id),
        3::bigint,
        'every workout exercise now names the target, the one that already did included'
    );
    RETURN NEXT is((SELECT count(*) FROM exercise_sets WHERE workout_exercise_id = _we), 1::bigint, 'the sets stayed with their workout exercise');
    RETURN NEXT is((SELECT exercise_id FROM template_exercises WHERE template_id = _t), _target_id, 'the routine names the target');
    RETURN NEXT is(
        (SELECT (exercise_id, chart_type, rest_timer) FROM exercise_preferences WHERE user_id = _user_id),
        (_target_id, 'totalReps'::text, 60),
        'the preference is the same row under the target'
    );
    RETURN NEXT is((SELECT count(*) FROM goals WHERE user_id = _user_id AND exercise_id = _target_id), 2::bigint, 'the goals name the target');
    RETURN NEXT is(
        (SELECT count(*) FROM workouts WHERE id IN (_w1, _w2) AND changed_xid = pg_current_xact_id()),
        2::bigint,
        'the moved workouts are stamped as changed, so the change feed carries them'
    );
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test__move_exercise_history_target_preference_wins() RETURNS SETOF TEXT AS
$$
DECLARE
    _user_id   TEXT;
    _source_id UUID;
    _target_id UUID;
    _r         RECORD;
BEGIN
    _user_id   := create_test_profile();
    _source_id := create_test_exercise('Mine', _user_id => _user_id);
    _target_id := create_test_exercise();
    RETURN NEXT is((SELECT count(*) FROM exercise_preferences WHERE user_id = _user_id), 0::bigint, 'no preferences yet');

    INSERT INTO exercise_preferences (user_id, exercise_id, chart_type, rest_timer, note)
    VALUES (_user_id, _source_id, 'totalReps', 60, 'from the source'),
           (_user_id, _target_id, NULL, 120, NULL);

    SELECT * INTO _r FROM _move_exercise_history(_user_id, _source_id, _target_id);

    RETURN NEXT is(_r.preferences_moved, 0, 'nothing moved: the target already had a row');
    RETURN NEXT is(_r.preferences_dropped, 1, 'the source''s row was dropped, and the drop is reported');
    RETURN NEXT is(_r.chart_preferences_moved, 0, 'the source''s chart setting went with its row');
    RETURN NEXT ok(_r.source_deleted, 'the custom was still deleted');
    RETURN NEXT is((SELECT count(*) FROM exercise_preferences WHERE user_id = _user_id), 1::bigint, 'one preference row remains');
    RETURN NEXT is(
        (SELECT (exercise_id, chart_type, rest_timer, note) FROM exercise_preferences WHERE user_id = _user_id),
        (_target_id, NULL::text, 120, NULL::text),
        'and it is the target''s, untouched'
    );
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test__move_exercise_history_keeps_library_source_others_rows() RETURNS SETOF TEXT AS
$$
DECLARE
    _user_id   TEXT;
    _other_id  TEXT;
    _source_id UUID;
    _target_id UUID;
    _w         UUID;
    _t         UUID;
    _r         RECORD;
BEGIN
    _user_id   := create_test_profile();
    _other_id  := create_test_profile();
    _source_id := create_test_exercise();
    _target_id := create_test_exercise();
    RETURN NEXT is((SELECT count(*) FROM workouts WHERE user_id IN (_user_id, _other_id)), 0::bigint, 'no workouts yet');

    _w := create_test_workout(_user_id => _user_id);
    PERFORM create_test_workout_exercise(_w, _source_id, 0);
    _w := create_test_workout(_user_id => _other_id);
    PERFORM create_test_workout_exercise(_w, _source_id, 0);
    _t := create_test_template(_user_id => _other_id);
    PERFORM create_test_template_exercise(_t, _source_id, 0);
    INSERT INTO exercise_preferences (user_id, exercise_id, rest_timer) VALUES (_other_id, _source_id, 45);

    SELECT * INTO _r FROM _move_exercise_history(_user_id, _source_id, _target_id);

    RETURN NEXT is(_r.workout_exercises_moved, 1, 'only the caller''s workout exercise moved');
    RETURN NEXT is(_r.template_exercises_moved, 0, 'the other user''s routine is not the caller''s');
    RETURN NEXT is(_r.preferences_moved, 0, 'nor is their preference');
    RETURN NEXT ok(NOT _r.source_deleted, 'a library exercise is never deleted');
    RETURN NEXT is((SELECT count(*) FROM exercises WHERE id = _source_id), 1::bigint, 'the library row is still there');
    RETURN NEXT is(
        (SELECT count(*) FROM workout_exercises we JOIN workouts w ON w.id = we.workout_id WHERE w.user_id = _other_id AND we.exercise_id = _source_id),
        1::bigint,
        'the other user''s workout still names the source'
    );
    RETURN NEXT is((SELECT exercise_id FROM template_exercises WHERE template_id = _t), _source_id, 'and so does their routine');
    RETURN NEXT is((SELECT exercise_id FROM exercise_preferences WHERE user_id = _other_id), _source_id, 'and their preference');
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test__move_exercise_history_dry_run_writes_nothing() RETURNS SETOF TEXT AS
$$
DECLARE
    _user_id   TEXT;
    _source_id UUID;
    _target_id UUID;
    _w         UUID;
    _t         UUID;
    _dry       RECORD;
    _wet       RECORD;
BEGIN
    _user_id   := create_test_profile();
    _source_id := create_test_exercise('Mine', _user_id => _user_id);
    _target_id := create_test_exercise();
    RETURN NEXT is((SELECT count(*) FROM workouts WHERE user_id = _user_id), 0::bigint, 'no workouts yet');

    _w := create_test_workout(_user_id => _user_id);
    PERFORM create_test_workout_exercise(_w, _source_id, 0);
    _t := create_test_template(_user_id => _user_id);
    PERFORM create_test_template_exercise(_t, _source_id, 0);
    INSERT INTO exercise_preferences (user_id, exercise_id, chart_type) VALUES (_user_id, _source_id, 'totalReps');
    INSERT INTO goals (user_id, metric, exercise_id, stages)
    VALUES (_user_id, 'totalReps', _source_id, '[{"id": "s1", "target": 100}]');
    -- as an earlier transaction would have left it
    UPDATE workouts SET changed_xid = '1'::xid8 WHERE id = _w;

    SELECT * INTO _dry FROM _move_exercise_history(_user_id, _source_id, _target_id, true);

    RETURN NEXT is((SELECT count(*) FROM exercises WHERE id = _source_id), 1::bigint, 'the custom is still there');
    RETURN NEXT is((SELECT exercise_id FROM workout_exercises WHERE workout_id = _w), _source_id, 'the workout still names the source');
    RETURN NEXT is((SELECT exercise_id FROM template_exercises WHERE template_id = _t), _source_id, 'so does the routine');
    RETURN NEXT is((SELECT exercise_id FROM exercise_preferences WHERE user_id = _user_id), _source_id, 'and the preference');
    RETURN NEXT is((SELECT exercise_id FROM goals WHERE user_id = _user_id), _source_id, 'and the goal');
    RETURN NEXT is((SELECT changed_xid FROM workouts WHERE id = _w), '1'::xid8, 'the workout is not stamped as changed');

    SELECT * INTO _wet FROM _move_exercise_history(_user_id, _source_id, _target_id, false);

    RETURN NEXT is(_dry, _wet, 'the dry run reported exactly what the move then did');
    RETURN NEXT is(_wet.workout_exercises_moved, 1, 'one workout exercise');
    RETURN NEXT is(_wet.template_exercises_moved, 1, 'one template exercise');
    RETURN NEXT is(_wet.preferences_moved, 1, 'one preference');
    RETURN NEXT is(_wet.preferences_dropped, 0, 'none dropped');
    RETURN NEXT is(_wet.chart_preferences_moved, 1, 'with a chart setting');
    RETURN NEXT is(_wet.goals_moved, 1, 'one goal');
    RETURN NEXT ok(_wet.source_deleted, 'and the custom deleted');
    RETURN NEXT is((SELECT count(*) FROM exercises WHERE id = _source_id), 0::bigint, 'the move deleted it');
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test__move_exercise_history_rekeys_programs() RETURNS SETOF TEXT AS
$$
DECLARE
    _user_id   TEXT;
    _source_id UUID;
    _target_id UUID;
    _moving    UUID;
    _both      UUID;
    _w         UUID;
    _dry       RECORD;
    _r         RECORD;
BEGIN
    _user_id   := create_test_profile();
    _source_id := create_test_exercise('Moving press', 'Barbell', 'Chest', _user_id);
    _target_id := create_test_exercise(_category => 'Barbell', _target => 'Chest');

    RETURN NEXT is((SELECT count(*) FROM programs WHERE user_id = _user_id), 0::bigint, 'no programs yet');
    RETURN NEXT is((SELECT count(*) FROM program_bases WHERE user_id = _user_id), 0::bigint, 'no bases yet');

    -- one program grows only the source; the other grows both
    INSERT INTO programs (user_id, name, rules)
    VALUES (_user_id, 'moving', jsonb_build_object(_source_id::text, '{"kind": "addWeight", "step": 2.5}'::jsonb))
    RETURNING id INTO _moving;
    INSERT INTO programs (user_id, name, rules)
    VALUES (
        _user_id,
        'both',
        jsonb_build_object(
            _source_id::text, '{"kind": "addWeight", "step": 2.5}'::jsonb,
            _target_id::text, '{"kind": "none"}'::jsonb
        )
    )
    RETURNING id INTO _both;
    _w := create_test_workout(_user_id => _user_id, _name => 'bumped both');

    INSERT INTO program_bases (user_id, program_id, exercise_id, value, workout_id, at)
    VALUES
        (_user_id, _moving, _source_id, 100, NULL, now() - interval '2 days'),
        (_user_id, _moving, _source_id, 102.5, _w, now() - interval '1 day'),
        (_user_id, _both, _source_id, 60, _w, now()),
        (_user_id, _both, _target_id, 70, _w, now());

    _dry := (SELECT r FROM _move_exercise_history(_user_id, _source_id, _target_id, true) r);
    RETURN NEXT is(_dry.programs_moved, 2, 'a dry run counts both programs');
    RETURN NEXT is(
            (SELECT count(*) FROM program_bases WHERE exercise_id = _source_id),
            3::bigint,
            'and writes nothing'
        );

    _r := (SELECT r FROM _move_exercise_history(_user_id, _source_id, _target_id) r);
    RETURN NEXT is(_r.programs_moved, 2, 'both programs moved');
    RETURN NEXT is(
            (SELECT rules -> _target_id::text ->> 'kind' FROM programs WHERE id = _moving),
            'addWeight',
            'a rule on the source alone moves to the target'
        );
    RETURN NEXT ok(
            NOT (SELECT rules ? _source_id::text FROM programs WHERE id = _moving),
            'and leaves the source'
        );
    RETURN NEXT is(
            (SELECT rules -> _target_id::text ->> 'kind' FROM programs WHERE id = _both),
            'none',
            'where both have a rule, the target''s wins'
        );
    RETURN NEXT is(
            (SELECT array_agg(value ORDER BY at) FROM program_bases WHERE program_id = _moving AND exercise_id = _target_id),
            ARRAY [100, 102.5]::real[],
            'the bases move with their history'
        );
    RETURN NEXT is(
            (SELECT array_agg(value) FROM program_bases WHERE program_id = _both),
            ARRAY [70]::real[],
            'one workout moves a base once: the source''s move from the same workout is dropped'
        );
    RETURN NEXT is(
            (SELECT count(*) FROM exercises WHERE id = _source_id),
            0::bigint,
            'the custom source is gone, and nothing of the programs went with it'
        );
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test__move_exercise_history_refuses_what_the_user_cannot_see() RETURNS SETOF TEXT AS
$$
DECLARE
    _user_id   TEXT;
    _other_id  TEXT;
    _theirs    UUID;
    _mine      UUID;
    _library   UUID;
BEGIN
    _user_id  := create_test_profile();
    _other_id := create_test_profile();
    _theirs   := create_test_exercise('Theirs', _user_id => _other_id);
    _mine     := create_test_exercise('Mine', _user_id => _user_id);
    _library  := create_test_exercise();

    RETURN NEXT throws_ok(
        format('SELECT * FROM _move_exercise_history(%L, %L, %L)', _user_id, _theirs, _library),
        'P0002',
        'exercise not found',
        'someone else''s custom as the source is not found, not forbidden'
    );
    RETURN NEXT throws_ok(
        format('SELECT * FROM _move_exercise_history(%L, %L, %L)', _user_id, _mine, _theirs),
        'P0002',
        'exercise not found',
        'someone else''s custom as the target is not found either'
    );
    RETURN NEXT throws_ok(
        format('SELECT * FROM _move_exercise_history(%L, %L, %L)', _user_id, _mine, '00000000-0000-7000-8000-000000000000'),
        'P0002',
        'exercise not found',
        'a missing target reads the same'
    );
    RETURN NEXT is((SELECT count(*) FROM exercises WHERE id IN (_theirs, _mine)), 2::bigint, 'nothing was deleted');
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test__move_exercise_history_rejects_source_equal_to_target() RETURNS SETOF TEXT AS
$$
DECLARE
    _user_id TEXT;
    _mine    UUID;
BEGIN
    _user_id := create_test_profile();
    _mine    := create_test_exercise('Mine', _user_id => _user_id);

    RETURN NEXT throws_ok(
        format('SELECT * FROM _move_exercise_history(%L, %L, %L)', _user_id, _mine, _mine),
        '22023',
        'source and target are the same exercise',
        'moving an exercise onto itself is refused'
    );
    RETURN NEXT is((SELECT count(*) FROM exercises WHERE id = _mine), 1::bigint, 'and the custom is kept');
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test__move_exercise_history_refuses_incompatible_target() RETURNS SETOF TEXT AS
$$
DECLARE
    _user_id  TEXT;
    _wheel    UUID;
    _ride     UUID;
    _dumbbell UUID;
    _assisted UUID;
    _we       UUID;
    _r        RECORD;
BEGIN
    _user_id  := create_test_profile();
    _wheel    := create_test_exercise('Ab wheel', 'Reps Only', 'Core', _user_id);
    _ride     := create_test_exercise('Ride', 'Cardio', 'Legs', _user_id);
    _dumbbell := create_test_exercise('Press', 'Dumbbell', 'Chest', _user_id);
    _assisted := create_test_exercise('Dip', 'Assisted Body Weight', 'Chest', _user_id);
    RETURN NEXT is((SELECT count(*) FROM workouts WHERE user_id = _user_id), 0::bigint, 'no workouts yet');

    _we := create_test_workout_exercise(create_test_workout(_user_id => _user_id), _wheel, 0);

    RETURN NEXT throws_ok(
        format('SELECT * FROM _move_exercise_history(%L, %L, %L, true)', _user_id, _wheel, _ride),
        '42804',
        'the target''s sets cannot hold the source''s',
        'a dry run refuses reps onto distance and time'
    );
    RETURN NEXT throws_ok(
        format('SELECT * FROM _move_exercise_history(%L, %L, %L)', _user_id, _wheel, _ride),
        '42804',
        'the target''s sets cannot hold the source''s',
        'and so does the move'
    );
    RETURN NEXT is((SELECT exercise_id FROM workout_exercises WHERE id = _we), _wheel, 'the sets stay where they were');
    RETURN NEXT throws_ok(
        format('SELECT * FROM _move_exercise_history(%L, %L, %L, true)', _user_id, _assisted, _dumbbell),
        '42804',
        'the target''s sets cannot hold the source''s',
        'assistance does not become load'
    );
    RETURN NEXT throws_ok(
        format('SELECT * FROM _move_exercise_history(%L, %L, %L, true)', _user_id, _dumbbell, _assisted),
        '42804',
        'the target''s sets cannot hold the source''s',
        'nor load assistance'
    );

    SELECT * INTO _r FROM _move_exercise_history(_user_id, _dumbbell, create_test_exercise(), true);
    RETURN NEXT ok(_r.source_deleted, 'a dumbbell lift moves onto a barbell one');
END
$$ LANGUAGE plpgsql;

SELECT * FROM runtests();

ROLLBACK;
