BEGIN;

CREATE OR REPLACE FUNCTION test__stamp_program_history_signature() RETURNS SETOF TEXT AS
$$
BEGIN
    RETURN NEXT has_function('public'::name, '_stamp_program_history'::name);
    RETURN NEXT function_lang_is('public'::name, '_stamp_program_history'::name, 'plpgsql'::name);
    RETURN NEXT function_returns('public'::name, '_stamp_program_history'::name, 'trigger');
    RETURN NEXT has_function('public'::name, '_stamp_program_histories'::name, ARRAY ['uuid[]']);
    RETURN NEXT function_lang_is('public'::name, '_stamp_program_histories'::name, ARRAY ['uuid[]'], 'sql'::name);
    RETURN NEXT function_returns('public'::name, '_stamp_program_histories'::name, ARRAY ['uuid[]'], 'void');
    RETURN NEXT trigger_is('public'::name, 'program_actions'::name, 'program_actions_stamp_insert'::name, 'public'::name, '_stamp_program_history'::name);
    RETURN NEXT trigger_is('public'::name, 'program_actions'::name, 'program_actions_stamp_update'::name, 'public'::name, '_stamp_program_history'::name);
    RETURN NEXT trigger_is('public'::name, 'program_actions'::name, 'program_actions_stamp_delete'::name, 'public'::name, '_stamp_program_history'::name);
    RETURN NEXT trigger_is('public'::name, 'program_bases'::name, 'program_bases_stamp_insert'::name, 'public'::name, '_stamp_program_history'::name);
    RETURN NEXT trigger_is('public'::name, 'program_bases'::name, 'program_bases_stamp_update'::name, 'public'::name, '_stamp_program_history'::name);
    RETURN NEXT trigger_is('public'::name, 'program_bases'::name, 'program_bases_stamp_delete'::name, 'public'::name, '_stamp_program_history'::name);
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test__stamp_program_history_follows_steps_and_bases() RETURNS SETOF TEXT AS
$$
DECLARE
    _user_id     TEXT;
    _program_id  UUID;
    _other_id    UUID;
    _exercise_id UUID;
    _action_id   UUID;
    _base_id     UUID;
BEGIN
    _user_id := create_test_profile();
    RETURN NEXT is((SELECT count(*) FROM programs WHERE user_id = _user_id), 0::bigint, 'no programs yet');
    RETURN NEXT is((SELECT count(*) FROM program_histories WHERE user_id = _user_id), 0::bigint, 'no histories yet');

    INSERT INTO programs (user_id, name) VALUES (_user_id, 'p') RETURNING id INTO _program_id;
    INSERT INTO programs (user_id, name) VALUES (_user_id, 'other') RETURNING id INTO _other_id;
    _exercise_id := create_test_exercise(_user_id => _user_id);
    RETURN NEXT is(
            (SELECT count(*) FROM program_histories WHERE user_id = _user_id),
            0::bigint,
            'a program with no history has no row'
        );

    INSERT INTO program_actions (user_id, program_id, kind, at)
    VALUES (_user_id, _program_id, 'pause', now())
    RETURNING id INTO _action_id;
    RETURN NEXT is(
            (SELECT changed_xid FROM program_histories WHERE program_id = _program_id),
            pg_current_xact_id(),
            'a step stamps its program'
        );
    RETURN NEXT is(
            (SELECT count(*) FROM program_histories WHERE program_id = _other_id),
            0::bigint,
            'and no other'
        );

    UPDATE program_histories SET changed_xid = '1' WHERE program_id = _program_id;
    INSERT INTO program_bases (user_id, program_id, exercise_id, value, at)
    VALUES (_user_id, _program_id, _exercise_id, 100, now())
    RETURNING id INTO _base_id;
    RETURN NEXT is(
            (SELECT changed_xid FROM program_histories WHERE program_id = _program_id),
            pg_current_xact_id(),
            'a base stamps it again'
        );

    UPDATE program_histories SET changed_xid = '1' WHERE program_id = _program_id;
    UPDATE program_bases SET at = at + INTERVAL '1 day' WHERE id = _base_id;
    RETURN NEXT is(
            (SELECT changed_xid FROM program_histories WHERE program_id = _program_id),
            pg_current_xact_id(),
            'so does a base changed'
        );

    UPDATE program_histories SET changed_xid = '1' WHERE program_id = _program_id;
    DELETE FROM program_bases WHERE id = _base_id;
    RETURN NEXT is(
            (SELECT changed_xid FROM program_histories WHERE program_id = _program_id),
            pg_current_xact_id(),
            'and a base removed'
        );

    UPDATE program_histories SET changed_xid = '1' WHERE program_id = _program_id;
    DELETE FROM program_actions WHERE id = _action_id;
    RETURN NEXT is(
            (SELECT changed_xid FROM program_histories WHERE program_id = _program_id),
            pg_current_xact_id(),
            'and a step undone, which leaves the row with nothing in it'
        );

    INSERT INTO program_actions (user_id, program_id, kind, at) VALUES (_user_id, _program_id, 'pause', now());
    DELETE FROM programs WHERE id = _program_id;
    RETURN NEXT is(
            (SELECT count(*) FROM program_histories WHERE program_id = _program_id),
            0::bigint,
            'a deleted program takes its row along'
        );
END
$$ LANGUAGE plpgsql;

SELECT * FROM runtests();

ROLLBACK;
