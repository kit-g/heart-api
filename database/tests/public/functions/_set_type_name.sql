BEGIN;

CREATE OR REPLACE FUNCTION test__set_type_name_signature() RETURNS SETOF TEXT AS
$$
BEGIN
    RETURN NEXT has_function('public'::name, '_set_type_name'::name, ARRAY ['character']);
    RETURN NEXT function_returns('public'::name, '_set_type_name'::name, ARRAY ['character'], 'text');
    RETURN NEXT function_lang_is('public'::name, '_set_type_name'::name, ARRAY ['character'], 'sql'::name);
    RETURN NEXT volatility_is('public'::name, '_set_type_name'::name, ARRAY ['character'], 'immutable');
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test__set_type_name_spells_out_every_letter() RETURNS SETOF TEXT AS
$$
BEGIN
    RETURN NEXT is(_set_type_name('n'), 'normal', 'n is normal');
    RETURN NEXT is(_set_type_name('w'), 'warmup', 'w is warmup');
    RETURN NEXT is(_set_type_name('d'), 'drop', 'd is drop');
    RETURN NEXT is(_set_type_name('f'), 'failure', 'f is failure');
    RETURN NEXT is(_set_type_name(NULL), NULL, 'not recorded stays NULL');
END
$$ LANGUAGE plpgsql;

SELECT * FROM runtests();

ROLLBACK;
