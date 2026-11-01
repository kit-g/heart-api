BEGIN;

CREATE OR REPLACE FUNCTION test__clean_up_device_tokens() RETURNS SETOF TEXT AS
$$
DECLARE
    _user TEXT := create_test_profile();
BEGIN
    RETURN NEXT has_function('public'::name, '_clean_up_device_tokens'::name);
    RETURN NEXT is((SELECT count(*) FROM device_tokens WHERE profile_id = _user), 0::bigint, 'no tokens yet');

    INSERT INTO device_tokens (profile_id, platform, token, last_seen_at)
    VALUES (_user, 'ios', _user || '-old', now() - INTERVAL '271 days'),
           (_user, 'ios', _user || '-new', now() - INTERVAL '269 days');

    PERFORM _clean_up_device_tokens();

    RETURN NEXT is(
        (SELECT array_agg(token) FROM device_tokens WHERE profile_id = _user),
        ARRAY [_user || '-new'],
        'only what has gone quiet goes'
    );
END
$$ LANGUAGE plpgsql;

SELECT * FROM runtests();

ROLLBACK;
