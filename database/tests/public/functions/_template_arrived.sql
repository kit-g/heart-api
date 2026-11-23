BEGIN;

CREATE OR REPLACE FUNCTION test__template_arrived_signature() RETURNS SETOF TEXT AS
$$
BEGIN
    RETURN NEXT has_function('public'::name, '_template_arrived'::name);
    RETURN NEXT function_lang_is('public'::name, '_template_arrived'::name, 'plpgsql'::name);
    RETURN NEXT function_returns('public'::name, '_template_arrived'::name, 'trigger');
    RETURN NEXT trigger_is(
            'public'::name, 'templates'::name,
            'templates_arrived'::name,
            'public'::name, '_template_arrived'::name
        );
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test__template_arrived_links_its_owners_workouts() RETURNS SETOF TEXT AS
$$
DECLARE
    _user_id     TEXT := create_test_profile();
    _other_id    TEXT := create_test_profile();
    _template_id UUID := uuidv7();
    _mine        UUID;
    _theirs      UUID;
BEGIN
    RETURN NEXT is((SELECT count(*) FROM templates WHERE id = _template_id), 0::bigint, 'not here yet');

    _mine := create_test_workout(_user_id => _user_id);
    _theirs := create_test_workout(_user_id => _other_id);
    UPDATE workouts SET sent_template_id = _template_id WHERE id IN (_mine, _theirs);

    INSERT INTO templates (id, user_id, name, order_index) VALUES (_template_id, _user_id, 'late', 0);

    RETURN NEXT results_eq(
            format('SELECT template_id, sent_template_id FROM workouts WHERE id = %L', _mine),
            format('VALUES (%L::uuid, NULL::uuid)', _template_id),
            'its owner''s workout is linked'
        );
    RETURN NEXT results_eq(
            format('SELECT template_id, sent_template_id FROM workouts WHERE id = %L', _theirs),
            format('VALUES (NULL::uuid, %L::uuid)', _template_id),
            'another account''s is not'
        );
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test__template_arrived_forgets_the_deletion() RETURNS SETOF TEXT AS
$$
DECLARE
    _user_id     TEXT := create_test_profile();
    _template_id UUID := create_test_template(_user_id => _user_id);
BEGIN
    DELETE FROM templates WHERE id = _template_id;
    RETURN NEXT is(
            (SELECT count(*) FROM archive.deleted_templates WHERE user_id = _user_id),
            1::bigint,
            'remembered once deleted'
        );

    INSERT INTO templates (id, user_id, name, order_index) VALUES (_template_id, _user_id, 'back', 0);
    RETURN NEXT is(
            (SELECT count(*) FROM archive.deleted_templates WHERE user_id = _user_id),
            0::bigint,
            'and not once put back'
        );
END
$$ LANGUAGE plpgsql;

SELECT * FROM runtests();

ROLLBACK;
