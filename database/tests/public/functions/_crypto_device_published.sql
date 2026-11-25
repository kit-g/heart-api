BEGIN;

CREATE OR REPLACE FUNCTION test__crypto_device_published_signature() RETURNS SETOF TEXT AS
$$
BEGIN
    RETURN NEXT has_function('public'::name, '_crypto_device_published'::name);
    RETURN NEXT function_lang_is('public'::name, '_crypto_device_published'::name, 'plpgsql'::name);
    RETURN NEXT function_returns('public'::name, '_crypto_device_published'::name, 'trigger');
    RETURN NEXT trigger_is(
            'public'::name, 'crypto_devices'::name,
            'crypto_devices_published'::name,
            'public'::name, '_crypto_device_published'::name
        );
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test__crypto_device_published_first_is_trusted() RETURNS SETOF TEXT AS
$$
DECLARE
    _user_id TEXT := create_test_profile();
    _first   UUID := uuidv7();
    _second  UUID := uuidv7();
    _again   UUID := uuidv7();
BEGIN
    RETURN NEXT is(
            (SELECT count(*) FROM crypto_devices WHERE user_id = _user_id),
            0::bigint,
            'no devices yet'
        );

    INSERT INTO crypto_devices (id, user_id, identity_key, signing_key, fallback_key)
    VALUES (_first, _user_id, 'i', 's', 'f');
    INSERT INTO crypto_devices (id, user_id, identity_key, signing_key, fallback_key)
    VALUES (_second, _user_id, 'i', 's', 'f');

    RETURN NEXT is((SELECT trust FROM crypto_devices WHERE id = _first), 'first', 'the first is trusted');
    RETURN NEXT is((SELECT trust FROM crypto_devices WHERE id = _second), NULL, 'the next is not, by itself');

    UPDATE crypto_devices SET removed_at = now() WHERE user_id = _user_id;
    INSERT INTO crypto_devices (id, user_id, identity_key, signing_key, fallback_key)
    VALUES (_again, _user_id, 'i', 's', 'f');
    RETURN NEXT is(
            (SELECT trust FROM crypto_devices WHERE id = _again),
            NULL,
            'one published once none is in use is not: a password could do that'
        );
END
$$ LANGUAGE plpgsql;

SELECT * FROM runtests();

ROLLBACK;
