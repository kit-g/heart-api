BEGIN;

CREATE OR REPLACE FUNCTION test__crypto_device_trusted_signature() RETURNS SETOF TEXT AS
$$
BEGIN
    RETURN NEXT has_function('public'::name, '_crypto_device_trusted'::name);
    RETURN NEXT function_lang_is('public'::name, '_crypto_device_trusted'::name, 'plpgsql'::name);
    RETURN NEXT function_returns('public'::name, '_crypto_device_trusted'::name, 'trigger');
    RETURN NEXT trigger_is(
            'public'::name, 'crypto_devices'::name,
            'crypto_devices_trusted'::name,
            'public'::name, '_crypto_device_trusted'::name
        );
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test__crypto_device_trusted_passes_down_vouches() RETURNS SETOF TEXT AS
$$
DECLARE
    _user_id TEXT := create_test_profile();
    _first   UUID := uuidv7();
    _parent  UUID := uuidv7();
    _child   UUID := uuidv7();
    _gone    UUID := uuidv7();
BEGIN
    RETURN NEXT is(
            (SELECT count(*) FROM crypto_devices WHERE user_id = _user_id),
            0::bigint,
            'no devices yet'
        );

    INSERT INTO crypto_devices (id, user_id, identity_key, signing_key, fallback_key)
    VALUES (_first, _user_id, 'i', 's', 'f'),
           (_parent, _user_id, 'i', 's', 'f');
    INSERT INTO crypto_devices (id, user_id, identity_key, signing_key, fallback_key, signature, vouched_by)
    VALUES (_child, _user_id, 'i', 's', 'f', 'sig', _parent);
    INSERT INTO crypto_devices (id, user_id, identity_key, signing_key, fallback_key, signature, vouched_by, removed_at)
    VALUES (_gone, _user_id, 'i', 's', 'f', 'sig', _child, now());
    RETURN NEXT is(
            (SELECT count(*) FROM crypto_devices WHERE user_id = _user_id AND trust IS NOT NULL),
            1::bigint,
            'only the first is trusted'
        );

    UPDATE crypto_devices SET trust = 'vouched', vouched_by = _first WHERE id = _parent;
    RETURN NEXT is((SELECT trust FROM crypto_devices WHERE id = _child), 'vouched', 'what it vouched for before is');
    RETURN NEXT is((SELECT trust FROM crypto_devices WHERE id = _gone), NULL, 'not a removed device');
END
$$ LANGUAGE plpgsql;

SELECT * FROM runtests();

ROLLBACK;
