BEGIN;

CREATE OR REPLACE FUNCTION test__shares_keys_with() RETURNS SETOF TEXT AS
$$
DECLARE
    _a TEXT := create_test_profile();
    _b TEXT := create_test_profile();
BEGIN
    RETURN NEXT has_function('public'::name, '_shares_keys_with'::name, ARRAY ['text', 'text']);
    RETURN NEXT ok(_shares_keys_with(_a, _a), 'yourself');
    RETURN NEXT ok(NOT _shares_keys_with(_a, _b), 'not a stranger');

    INSERT INTO connections (initiator_id, target_id, initiator_role, target_role, domain, status)
    VALUES (_a, _b, 'COACH', 'STUDENT', 'fitness', 'pending');
    RETURN NEXT ok(NOT _shares_keys_with(_a, _b), 'not on a request nobody answered');

    UPDATE connections SET status = 'active' WHERE initiator_id = _a;
    RETURN NEXT ok(_shares_keys_with(_a, _b), 'a live relationship');
    RETURN NEXT ok(_shares_keys_with(_b, _a), 'either way');

    UPDATE connections SET status = 'severed' WHERE initiator_id = _a;
    RETURN NEXT ok(_shares_keys_with(_a, _b), 'an ended one: a new phone still needs keys for the history');

    INSERT INTO blocks (blocker_id, blocked_id) VALUES (_b, _a);
    RETURN NEXT ok(NOT _shares_keys_with(_a, _b), 'never across a block');
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test__clean_up_device_queue() RETURNS SETOF TEXT AS
$$
DECLARE
    _a TEXT := create_test_profile();
    _d UUID := uuidv7();
BEGIN
    RETURN NEXT has_function('public'::name, '_clean_up_device_queue'::name);

    INSERT INTO crypto_devices (id, user_id, identity_key, signing_key, fallback_key) VALUES (_d, _a, 'i', 's', 'f');
    RETURN NEXT is((SELECT count(*) FROM device_queue WHERE recipient_device_id = _d), 0::bigint, 'nothing waiting yet');

    INSERT INTO device_queue (id, recipient_device_id, kind, content, created_at)
    VALUES (uuidv7(), _d, 'key', 'x', now() - INTERVAL '91 days'),
           (uuidv7(), _d, 'key', 'y', now() - INTERVAL '89 days');
    PERFORM _clean_up_device_queue();

    RETURN NEXT is(
        (SELECT array_agg(content) FROM device_queue WHERE recipient_device_id = _d),
        ARRAY ['y'],
        'kept for at least 90 days'
    );
END
$$ LANGUAGE plpgsql;

SELECT * FROM runtests();

ROLLBACK;
