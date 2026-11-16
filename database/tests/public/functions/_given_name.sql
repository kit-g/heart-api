BEGIN;

CREATE OR REPLACE FUNCTION test__given_name() RETURNS SETOF TEXT AS
$$
DECLARE
    _coach   TEXT := create_test_profile();
    _student TEXT := create_test_profile();
    _other   TEXT := create_test_profile();
    _first   UUID;
    _second  UUID;
BEGIN
    RETURN NEXT has_function('public'::name, '_given_name'::name, ARRAY ['text', 'text']);
    RETURN NEXT function_returns('public'::name, '_given_name'::name, ARRAY ['text', 'text'], 'text');
    RETURN NEXT function_lang_is('public'::name, '_given_name'::name, ARRAY ['text', 'text'], 'sql'::name);
    RETURN NEXT has_function('public'::name, '_invited_as'::name, ARRAY ['text', 'text']);
    RETURN NEXT function_returns('public'::name, '_invited_as'::name, ARRAY ['text', 'text'], 'text');

    RETURN NEXT is((SELECT count(*) FROM given_names WHERE giver_id = _coach), 0::bigint, 'no names yet');
    RETURN NEXT is((SELECT count(*) FROM invitations WHERE inviter_id = _coach), 0::bigint, 'no invitations yet');
    RETURN NEXT is(_given_name(_coach, _student), NULL, 'nothing given');

    INSERT INTO invitations (inviter_id, token_hash, name, expires_at)
    VALUES (_coach, decode(md5(random()::text), 'hex'), 'Sam from the gym', now() + INTERVAL '1 day')
    RETURNING id INTO _first;
    RETURN NEXT is(_given_name(_coach, _student), NULL, 'an invitation nobody accepted');

    INSERT INTO invitation_responses (invitation_id, user_id, response, at)
    VALUES (_first, _student, 'accepted', now() - INTERVAL '1 day');
    RETURN NEXT is(_given_name(_coach, _student), 'Sam from the gym', 'the accepted invitation''s name');
    RETURN NEXT is(_given_name(_student, _coach), NULL, 'only the inviter''s');
    RETURN NEXT is(_given_name(_other, _student), NULL, 'nobody else''s');

    INSERT INTO invitations (inviter_id, token_hash, name, expires_at)
    VALUES (_coach, decode(md5(random()::text), 'hex'), 'Sam again', now() + INTERVAL '1 day')
    RETURNING id INTO _second;
    INSERT INTO invitation_responses (invitation_id, user_id, response) VALUES (_second, _student, 'declined');
    RETURN NEXT is(_given_name(_coach, _student), 'Sam from the gym', 'not a declined one');

    UPDATE invitation_responses SET response = 'accepted', at = now() WHERE invitation_id = _second;
    RETURN NEXT is(_given_name(_coach, _student), 'Sam again', 'the last one accepted');

    INSERT INTO given_names (giver_id, person_id, name) VALUES (_coach, _student, 'Samantha');
    RETURN NEXT is(_given_name(_coach, _student), 'Samantha', 'a name set wins');
    RETURN NEXT is(_invited_as(_coach, _student), 'Sam again', 'and the invitation''s stays beside it');

    DELETE FROM given_names WHERE giver_id = _coach;
    RETURN NEXT is(_given_name(_coach, _student), 'Sam again', 'cleared, back to the invitation');
END
$$ LANGUAGE plpgsql;

SELECT * FROM runtests();

ROLLBACK;
