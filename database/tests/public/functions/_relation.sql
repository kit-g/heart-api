BEGIN;

CREATE OR REPLACE FUNCTION test__relation_signature() RETURNS SETOF TEXT AS
$$
BEGIN
    RETURN NEXT has_function('public'::name, '_relation'::name, ARRAY ['text', 'text']);
    RETURN NEXT function_returns('public'::name, '_relation'::name, ARRAY ['text', 'text'], 'relation');
    RETURN NEXT function_lang_is('public'::name, '_relation'::name, ARRAY ['text', 'text'], 'plpgsql'::name);
    RETURN NEXT has_function('public'::name, '_blocked_between'::name, ARRAY ['text', 'text']);
    RETURN NEXT has_function('public'::name, '_readable_at'::name, ARRAY ['relation', 'timestamp with time zone', 'timestamp with time zone']);
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test__relation_folds_a_pairs_rows() RETURNS SETOF TEXT AS
$$
DECLARE
    _coach   TEXT := create_test_profile();
    _student TEXT := create_test_profile();
    _r       relation;
BEGIN
    RETURN NEXT is((_relation(_coach, _coach)).scope, 'self', 'yourself');
    RETURN NEXT is((_relation(_coach, _student)).scope, NULL, 'strangers read nothing');

    INSERT INTO connections (initiator_id, target_id, initiator_role, target_role, domain, status)
    VALUES (_coach, _student, 'COACH', 'STUDENT', 'fitness', 'pending');
    RETURN NEXT is((_relation(_coach, _student)).scope, NULL, 'a pending row opens nothing');

    INSERT INTO connections (initiator_id, target_id, initiator_role, target_role, domain, status)
    VALUES (_coach, _student, 'PEER', 'PEER', 'general', 'active');
    RETURN NEXT is((_relation(_coach, _student)).scope, 'peer', 'a peer row alone is a peer''s view');

    UPDATE connections SET status = 'active', shares = '{goals}' WHERE domain = 'fitness' AND initiator_id = _coach;
    _r := _relation(_coach, _student);
    RETURN NEXT is(_r.scope, 'coach', 'a coach''s view wins over a peer''s');
    RETURN NEXT is(_r.active, TRUE, 'and it is active');
    RETURN NEXT is(_r.shares, ARRAY ['goals'], 'with what the student shared');
    RETURN NEXT is((_relation(_student, _coach)).scope, 'peer', 'the student''s peer view of their coach stays');

    UPDATE connections SET status = 'paused' WHERE domain = 'fitness' AND initiator_id = _coach;
    _r := _relation(_coach, _student);
    RETURN NEXT is(_r.scope, 'coach', 'a pause keeps the coach''s view, not a peer''s');
    RETURN NEXT is(_r.active, FALSE, 'and it is not active');
    RETURN NEXT ok(_r.pauses @> clock_timestamp(), 'and the window is open');

    UPDATE connections SET status = 'blocked', status_by = _student WHERE domain = 'general' AND initiator_id = _coach;
    RETURN NEXT is((_relation(_coach, _student)).scope, NULL, 'a block in one domain answers nothing for the pair');
    RETURN NEXT is((_relation(_student, _coach)).scope, NULL, 'in either direction');
    RETURN NEXT is(_blocked_between(_student, _coach), TRUE, 'whichever way it is asked');

    UPDATE connections SET status = 'severed', status_by = _student WHERE domain = 'general' AND initiator_id = _coach;
    RETURN NEXT is(_blocked_between(_student, _coach), FALSE, 'moving out of blocked lifts it');
    RETURN NEXT is(
        (SELECT count(*) FROM blocks WHERE blocker_id = _student AND lifted_at IS NOT NULL),
        1::bigint,
        'and the block stays as history'
    );
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test__readable_at_limits_by_scope() RETURNS SETOF TEXT AS
$$
DECLARE
    _since  TIMESTAMPTZ := '2026-06-01Z';
    _coach  relation := ROW ('coach', TRUE, _since, '{}', tstzmultirange(tstzrange('2026-07-01Z', '2026-08-01Z')));
    _shared relation := ROW ('coach', TRUE, _since, '{history}', NULL);
    _peer   relation := ROW ('peer', TRUE, NULL, '{}', NULL);
    _self   relation := ROW ('self', TRUE, NULL, '{}', NULL);
    _none   relation := ROW (NULL, FALSE, NULL, '{}', NULL);
BEGIN
    RETURN NEXT ok(_readable_at(_self, '2020-01-01Z', now()), 'you read your own, hidden too');
    RETURN NEXT ok(_readable_at(_peer, '2020-01-01Z', NULL), 'a peer reads any time');
    RETURN NEXT ok(NOT _readable_at(_peer, '2026-06-02Z', now()), 'but not what is hidden');
    RETURN NEXT ok(_readable_at(_coach, '2026-06-02Z', NULL), 'a coach reads from acceptance');
    RETURN NEXT ok(NOT _readable_at(_coach, '2026-05-01Z', NULL), 'not before it');
    RETURN NEXT ok(_readable_at(_shared, '2026-05-01Z', NULL), 'unless history is shared');
    RETURN NEXT ok(NOT _readable_at(_coach, '2026-07-02Z', NULL), 'not during a pause');
    RETURN NEXT ok(_readable_at(_coach, '2026-08-02Z', NULL), 'and again after it');
    RETURN NEXT ok(NOT _readable_at(_coach, '2026-06-02Z', now()), 'never what is hidden');
    RETURN NEXT ok(NOT _readable_at(_none, '2026-06-02Z', NULL), 'nothing without a relation');
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test__connection_triggers() RETURNS SETOF TEXT AS
$$
DECLARE
    _a  TEXT := create_test_profile();
    _b  TEXT := create_test_profile();
    _id UUID;
BEGIN
    INSERT INTO connections (initiator_id, target_id, initiator_role, target_role, domain, status_by)
    VALUES (_a, _b, 'PEER', 'PEER', 'fitness', _a)
    RETURNING id INTO _id;

    RETURN NEXT is((SELECT count(*) FROM connection_events WHERE connection_id = _id), 1::bigint, 'the first status');
    RETURN NEXT is((SELECT accepted_at FROM connections WHERE id = _id), NULL, 'not accepted yet');

    UPDATE connections SET status = 'active', status_by = _b WHERE id = _id;
    RETURN NEXT is((SELECT count(*) FROM connection_events WHERE connection_id = _id), 2::bigint, 'each move');
    RETURN NEXT ok((SELECT accepted_at IS NOT NULL FROM connections WHERE id = _id), 'dated on becoming active');
    RETURN NEXT is(
        (SELECT actor_id FROM connection_events WHERE connection_id = _id ORDER BY id DESC LIMIT 1),
        _b,
        'with who moved it'
    );

    UPDATE connections SET shares = '{goals}' WHERE id = _id;
    RETURN NEXT is((SELECT count(*) FROM connection_events WHERE connection_id = _id), 2::bigint, 'only status moves count');
END
$$ LANGUAGE plpgsql;

SELECT * FROM runtests();

ROLLBACK;
