BEGIN;

CREATE OR REPLACE FUNCTION test__set_type_code_signature() RETURNS SETOF TEXT AS
$$
BEGIN
    RETURN NEXT has_function('public'::name, '_set_type_code'::name, ARRAY ['text']);
    RETURN NEXT function_returns('public'::name, '_set_type_code'::name, ARRAY ['text'], 'character');
    RETURN NEXT function_lang_is('public'::name, '_set_type_code'::name, ARRAY ['text'], 'plpgsql'::name);
    RETURN NEXT volatility_is('public'::name, '_set_type_code'::name, ARRAY ['text'], 'immutable');
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test__set_type_code_stores_every_word() RETURNS SETOF TEXT AS
$$
BEGIN
    RETURN NEXT is(_set_type_code('warmup'), 'w', 'warmup is w');
    RETURN NEXT is(_set_type_code('drop'), 'd', 'drop is d');
    RETURN NEXT is(_set_type_code('failure'), 'f', 'failure is f');
    RETURN NEXT is(_set_type_code('normal'), NULL, 'normal is NULL');
    RETURN NEXT is(_set_type_code(NULL), NULL, 'NULL is NULL');
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test__set_type_code_reverses_the_name() RETURNS SETOF TEXT AS
$$
BEGIN
    RETURN NEXT is(
        (SELECT array_agg(_set_type_name(_set_type_code(w)) ORDER BY w)
         FROM unnest(ARRAY ['drop', 'failure', 'normal', 'warmup']) w),
        ARRAY ['drop', 'failure', 'normal', 'warmup'],
        'every word survives the round trip through its letter'
    );
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test__set_type_code_refuses_an_unknown_word() RETURNS SETOF TEXT AS
$$
BEGIN
    RETURN NEXT throws_ok(
        $q$ SELECT _set_type_code('amrap') $q$,
        '22023',
        'unknown set type: amrap',
        'an unknown word raises rather than storing a normal set'
    );
    RETURN NEXT throws_ok(
        $q$ SELECT _set_type_code('w') $q$,
        '22023',
        NULL,
        'a letter is not a word'
    );
END
$$ LANGUAGE plpgsql;

SELECT * FROM runtests();

ROLLBACK;
