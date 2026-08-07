BEGIN;

CREATE OR REPLACE FUNCTION test_uuidv7_signature() RETURNS SETOF TEXT AS
$$
BEGIN
    RETURN NEXT has_function('public'::name, 'uuidv7'::name);
    RETURN NEXT function_returns('public'::name, 'uuidv7'::name, 'uuid');
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test_uuidv7_returns_distinct_values() RETURNS SETOF TEXT AS
$$
BEGIN
    RETURN NEXT isnt(uuidv7(), uuidv7(), 'two calls return different uuids');
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test_uuidv7_version_nibble_is_7() RETURNS SETOF TEXT AS
$$
DECLARE
    _u TEXT;
BEGIN
    -- v7 stamps version 7 into the 13th hex character (1-indexed)
    -- e.g. xxxxxxxx-xxxx-7xxx-xxxx-xxxxxxxxxxxx
    _u := uuidv7()::text;
    RETURN NEXT is(substr(_u, 15, 1), '7', 'version nibble is 7');
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test_uuidv7_is_sortable_by_time() RETURNS SETOF TEXT AS
$$
DECLARE
    _a UUID;
    _b UUID;
    _c UUID;
BEGIN
    _a := uuidv7();
    PERFORM pg_sleep(0.002);
    _b := uuidv7();
    PERFORM pg_sleep(0.002);
    _c := uuidv7();

    RETURN NEXT ok(_a < _b, 'earlier call sorts before later call (a < b)');
    RETURN NEXT ok(_b < _c, 'monotonic across multiple calls (b < c)');
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test_uuidv7_sub_ms_signature() RETURNS SETOF TEXT AS
$$
BEGIN
    RETURN NEXT has_function('public'::name, 'uuidv7_sub_ms'::name, ARRAY ['timestamptz']);
    RETURN NEXT function_returns('public'::name, 'uuidv7_sub_ms'::name, ARRAY ['timestamptz'], 'uuid');
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test_uuidv7_sub_ms_orders_by_time() RETURNS SETOF TEXT AS
$$
DECLARE
    _t TIMESTAMPTZ := '2026-01-02 03:04:05.678+00';
BEGIN
    RETURN NEXT is(substr(uuidv7_sub_ms(_t)::text, 15, 1), '7', 'version nibble is 7');
    RETURN NEXT ok(
            uuidv7_sub_ms(_t) < uuidv7_sub_ms(_t + interval '1 millisecond'),
            'a later timestamp sorts after an earlier one'
        );
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test_uuidv7_extract_signature() RETURNS SETOF TEXT AS
$$
BEGIN
    RETURN NEXT has_function('public'::name, 'uuidv7_extract_timestamp'::name, ARRAY ['uuid']);
    RETURN NEXT function_returns('public'::name, 'uuidv7_extract_timestamp'::name, ARRAY ['uuid'], 'timestamp with time zone');
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test_uuidv7_extract_round_trips() RETURNS SETOF TEXT AS
$$
DECLARE
    -- exact millisecond, so the 48-bit ms field holds it losslessly
    _t TIMESTAMPTZ := '2026-01-02 03:04:05.678+00';
BEGIN
    RETURN NEXT is(
            uuidv7_extract_timestamp(uuidv7(_t)),
            _t,
            'uuidv7 -> extract round-trips an exact-ms timestamp'
        );
    RETURN NEXT is(
            uuidv7_extract_timestamp(uuidv7_boundary(_t)),
            _t,
            'boundary -> extract round-trips an exact-ms timestamp'
        );
    RETURN NEXT ok(
            abs(extract(epoch from uuidv7_extract_timestamp(uuidv7_sub_ms(_t)) - _t)) < 0.001,
            'sub_ms -> extract lands within a millisecond'
        );
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test_uuidv7_boundary_signature() RETURNS SETOF TEXT AS
$$
BEGIN
    RETURN NEXT has_function('public'::name, 'uuidv7_boundary'::name, ARRAY ['timestamptz']);
    RETURN NEXT function_returns('public'::name, 'uuidv7_boundary'::name, ARRAY ['timestamptz'], 'uuid');
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test_uuidv7_boundary_is_lower_bound() RETURNS SETOF TEXT AS
$$
DECLARE
    _t TIMESTAMPTZ := '2026-01-02 03:04:05.678+00';
BEGIN
    -- all random bits zero: nothing generated for _t can sort below it,
    -- and everything generated for earlier timestamps sorts below it
    RETURN NEXT ok(uuidv7_boundary(_t) <= uuidv7(_t), 'boundary(t) <= uuidv7(t)');
    RETURN NEXT ok(uuidv7_boundary(_t) <= uuidv7_sub_ms(_t), 'boundary(t) <= uuidv7_sub_ms(t)');
    RETURN NEXT ok(
            uuidv7_boundary(_t + interval '1 millisecond') > uuidv7(_t),
            'boundary of the next ms sorts above anything from this ms'
        );
END
$$ LANGUAGE plpgsql;

SELECT * FROM runtests();

ROLLBACK;
