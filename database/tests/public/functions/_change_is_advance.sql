BEGIN;

CREATE OR REPLACE FUNCTION test__change_is_advance_signature() RETURNS SETOF TEXT AS
$$
BEGIN
    RETURN NEXT has_function('public'::name, '_change_is_advance'::name, ARRAY ['jsonb', 'jsonb', 'uuid', 'uuid']);
    RETURN NEXT function_returns('public'::name, '_change_is_advance'::name, ARRAY ['jsonb', 'jsonb', 'uuid', 'uuid'], 'boolean');
    RETURN NEXT function_lang_is('public'::name, '_change_is_advance'::name, ARRAY ['jsonb', 'jsonb', 'uuid', 'uuid'], 'sql'::name);
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test__change_is_advance_of_a_session() RETURNS SETOF TEXT AS
$$
DECLARE
    _a      UUID := uuidv7();
    _b      UUID := uuidv7();
    _c      UUID := uuidv7();
    _before JSONB := jsonb_build_object('name', 'Day', 'exercises', jsonb_build_array(
        jsonb_build_object('exercise', jsonb_build_object('id', _a), 'sets', '[]'::jsonb),
        jsonb_build_object('exercise', jsonb_build_object('id', _c), 'sets', '[]'::jsonb)
    ));
    _after  JSONB := jsonb_build_object('name', 'Day', 'exercises', jsonb_build_array(
        jsonb_build_object('exercise', jsonb_build_object('id', _b), 'sets', '[1]'::jsonb),
        jsonb_build_object('exercise', jsonb_build_object('id', _c), 'sets', '[]'::jsonb)
    ));
BEGIN
    RETURN NEXT ok(_change_is_advance(_before, _after, _a, _b), 'the next exercise in the same place');
    RETURN NEXT ok(NOT _change_is_advance(_before, _after, _a, _c), 'another step is not this change');
    RETURN NEXT ok(NOT _change_is_advance(_before, _after || '{"name": "Mine"}', _a, _b), 'a rename besides');
    RETURN NEXT ok(NOT _change_is_advance(_after, _after || '{"note": "x"}', _a, _b), 'one that never held the exercise');
    RETURN NEXT ok(NOT _change_is_advance(NULL, _after, _a, _b), 'one just made');
    RETURN NEXT ok(NOT _change_is_advance(_before, NULL, _a, _b), 'one just deleted');
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test__change_is_advance_of_a_program() RETURNS SETOF TEXT AS
$$
DECLARE
    _a      UUID := uuidv7();
    _b      UUID := uuidv7();
    _before JSONB := jsonb_build_object('name', 'Block', 'revision', 1, 'rules', jsonb_build_object(_a, '{"kind": "ladder"}'::jsonb));
    _after  JSONB := jsonb_build_object('name', 'Block', 'revision', 2, 'rules', jsonb_build_object(_b, '{"kind": "ladder"}'::jsonb));
BEGIN
    RETURN NEXT ok(_change_is_advance(_before, _after, _a, _b), 'the rule moves to the next exercise');
    RETURN NEXT ok(NOT _change_is_advance(_before, _after || '{"weeks": 3}', _a, _b), 'and something else');
    RETURN NEXT ok(
            NOT _change_is_advance(_before, jsonb_set(_after, ARRAY ['rules', _b::text], '{"kind": "step"}'), _a, _b),
            'a rule changed as it moved'
        );
    RETURN NEXT ok(NOT _change_is_advance('{"rules": 1}', '{"rules": 1}', _a, _b), 'rules of another shape');
END
$$ LANGUAGE plpgsql;

SELECT * FROM runtests();

ROLLBACK;
