BEGIN;

CREATE OR REPLACE FUNCTION test__stamp_program_join_signature() RETURNS SETOF TEXT AS
$$
BEGIN
    RETURN NEXT has_function('public'::name, '_stamp_program_join'::name);
    RETURN NEXT function_lang_is('public'::name, '_stamp_program_join'::name, 'plpgsql'::name);
    RETURN NEXT function_returns('public'::name, '_stamp_program_join'::name, 'trigger');
    RETURN NEXT trigger_is(
            'public'::name, 'templates'::name,
            'templates_stamp_program_join'::name,
            'public'::name, '_stamp_program_join'::name
        );
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test__stamp_program_join_follows_program_id() RETURNS SETOF TEXT AS
$$
DECLARE
    _user_id     TEXT;
    _program_id  UUID;
    _template_id UUID;
    _joined      TIMESTAMPTZ;
BEGIN
    _user_id := create_test_profile();
    RETURN NEXT is((SELECT count(*) FROM programs WHERE user_id = _user_id), 0::bigint, 'no programs yet');
    RETURN NEXT is((SELECT count(*) FROM templates WHERE user_id = _user_id), 0::bigint, 'no templates yet');

    INSERT INTO programs (user_id, name) VALUES (_user_id, 'p') RETURNING id INTO _program_id;
    _template_id := create_test_template(_user_id => _user_id);

    RETURN NEXT is(
            (SELECT joined_program_at FROM templates WHERE id = _template_id),
            NULL,
            'a plain template has joined nothing'
        );

    UPDATE templates SET program_id = _program_id WHERE id = _template_id;
    _joined := (SELECT joined_program_at FROM templates WHERE id = _template_id);
    RETURN NEXT ok(_joined IS NOT NULL, 'filing it into a program stamps when');

    UPDATE templates SET name = 'renamed' WHERE id = _template_id;
    RETURN NEXT is(
            (SELECT joined_program_at FROM templates WHERE id = _template_id),
            _joined,
            'an edit that leaves the program alone keeps the stamp'
        );

    UPDATE templates SET joined_program_at = '2020-01-01', program_id = _program_id WHERE id = _template_id;
    RETURN NEXT is(
            (SELECT joined_program_at FROM templates WHERE id = _template_id),
            '2020-01-01'::timestamptz,
            'the same program written again is no new join'
        );

    UPDATE templates SET program_id = NULL WHERE id = _template_id;
    RETURN NEXT is(
            (SELECT joined_program_at FROM templates WHERE id = _template_id),
            NULL,
            'leaving the program clears it'
        );
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test__stamp_program_join_takes_the_device_time() RETURNS SETOF TEXT AS
$$
DECLARE
    _user_id     TEXT;
    _first       UUID;
    _second      UUID;
    _template_id UUID;
BEGIN
    _user_id := create_test_profile();
    RETURN NEXT is((SELECT count(*) FROM programs WHERE user_id = _user_id), 0::bigint, 'no programs yet');
    RETURN NEXT is((SELECT count(*) FROM templates WHERE user_id = _user_id), 0::bigint, 'no templates yet');

    INSERT INTO programs (user_id, name) VALUES (_user_id, 'first') RETURNING id INTO _first;
    INSERT INTO programs (user_id, name) VALUES (_user_id, 'second') RETURNING id INTO _second;

    INSERT INTO templates (user_id, name, program_id, joined_program_at)
    VALUES (_user_id, 'filed offline', _first, '2026-01-01T08:00:00Z')
    RETURNING id INTO _template_id;
    RETURN NEXT is(
            (SELECT joined_program_at FROM templates WHERE id = _template_id),
            '2026-01-01T08:00:00Z'::timestamptz,
            'a session created in a program joins when the device says'
        );

    UPDATE templates SET program_id = _second WHERE id = _template_id;
    RETURN NEXT ok(
            (SELECT joined_program_at FROM templates WHERE id = _template_id) > '2026-01-01T08:00:00Z'::timestamptz,
            'moving to another program without a time does not keep the old program''s'
        );

    UPDATE templates SET program_id = _first, joined_program_at = '2026-02-01T08:00:00Z' WHERE id = _template_id;
    RETURN NEXT is(
            (SELECT joined_program_at FROM templates WHERE id = _template_id),
            '2026-02-01T08:00:00Z'::timestamptz,
            'moving with a time takes it'
        );

    UPDATE templates SET joined_program_at = now() + INTERVAL '1 day' WHERE id = _template_id;
    RETURN NEXT ok(
            (SELECT joined_program_at FROM templates WHERE id = _template_id) <= now(),
            'a clock ahead is capped at now'
        );
END
$$ LANGUAGE plpgsql;

SELECT * FROM runtests();

ROLLBACK;
