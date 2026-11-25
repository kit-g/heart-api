BEGIN;

CREATE OR REPLACE FUNCTION test__crypto_device_removed_signature() RETURNS SETOF TEXT AS
$$
BEGIN
    RETURN NEXT has_function('public'::name, '_crypto_device_removed'::name);
    RETURN NEXT function_lang_is('public'::name, '_crypto_device_removed'::name, 'plpgsql'::name);
    RETURN NEXT function_returns('public'::name, '_crypto_device_removed'::name, 'trigger');
    RETURN NEXT trigger_is(
            'public'::name, 'crypto_devices'::name,
            'crypto_devices_removed'::name,
            'public'::name, '_crypto_device_removed'::name
        );
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test__crypto_device_removed_vouches_for_nothing() RETURNS SETOF TEXT AS
$$
DECLARE
    _user_id TEXT := create_test_profile();
    _voucher UUID := uuidv7();
    _vouched UUID := uuidv7();
    _other   UUID := uuidv7();
BEGIN
    RETURN NEXT is(
            (SELECT count(*) FROM crypto_devices WHERE user_id = _user_id),
            0::bigint,
            'no devices yet'
        );

    INSERT INTO crypto_devices (id, user_id, identity_key, signing_key, fallback_key)
    VALUES (_voucher, _user_id, 'i', 's', 'f'),
           (_other, _user_id, 'i', 's', 'f');
    INSERT INTO crypto_devices (id, user_id, identity_key, signing_key, fallback_key, signature, vouched_by)
    VALUES (_vouched, _user_id, 'i', 's', 'f', 'sig', _voucher);

    UPDATE crypto_devices SET fallback_key = 'g' WHERE id = _voucher;
    RETURN NEXT is(
            (SELECT vouched_by FROM crypto_devices WHERE id = _vouched),
            _voucher,
            'another change to the voucher leaves the vouch'
        );

    UPDATE crypto_devices SET removed_at = now() WHERE id = _other;
    RETURN NEXT is(
            (SELECT vouched_by FROM crypto_devices WHERE id = _vouched),
            _voucher,
            'removing a device that vouched for nothing leaves the vouch'
        );

    UPDATE crypto_devices SET removed_at = now() WHERE id = _voucher;
    RETURN NEXT is(
            (SELECT (vouched_by, signature) IS NULL FROM crypto_devices WHERE id = _vouched),
            true,
            'removing the voucher leaves it vouched for by nobody'
        );
END
$$ LANGUAGE plpgsql;

SELECT * FROM runtests();

ROLLBACK;
