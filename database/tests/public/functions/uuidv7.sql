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

SELECT * FROM runtests();

ROLLBACK;
