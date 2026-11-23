BEGIN;

CREATE OR REPLACE FUNCTION test__template_deleted_signature() RETURNS SETOF TEXT AS
$$
BEGIN
    RETURN NEXT has_function('public'::name, '_template_deleted'::name);
    RETURN NEXT function_lang_is('public'::name, '_template_deleted'::name, 'plpgsql'::name);
    RETURN NEXT function_returns('public'::name, '_template_deleted'::name, 'trigger');
    RETURN NEXT trigger_is(
            'public'::name, 'templates'::name,
            'templates_deleted'::name,
            'public'::name, '_template_deleted'::name
        );
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test__template_deleted_is_remembered_and_named_by_nothing() RETURNS SETOF TEXT AS
$$
DECLARE
    _user_id     TEXT := create_test_profile();
    _template_id UUID := create_test_template(_user_id => _user_id);
    _linked      UUID;
    _unlinked    UUID;
BEGIN
    RETURN NEXT is(
            (SELECT count(*) FROM archive.deleted_templates WHERE user_id = _user_id),
            0::bigint,
            'nothing deleted yet'
        );

    _linked := create_test_workout(_user_id => _user_id);
    _unlinked := create_test_workout(_user_id => _user_id);
    UPDATE workouts SET template_id = _template_id WHERE id = _linked;
    UPDATE workouts SET sent_template_id = _template_id WHERE id = _unlinked;

    DELETE FROM templates WHERE id = _template_id;

    RETURN NEXT results_eq(
            format('SELECT id FROM archive.deleted_templates WHERE user_id = %L', _user_id),
            format('VALUES (%L::uuid)', _template_id),
            'remembered by its id'
        );
    RETURN NEXT is(
            (
                SELECT count(*)
                FROM workouts
                WHERE id IN (_linked, _unlinked)
                  AND coalesce(template_id, sent_template_id) IS NOT NULL
            ),
            0::bigint,
            'no workout names it'
        );
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test__template_deleted_with_its_account() RETURNS SETOF TEXT AS
$$
DECLARE
    _user_id     TEXT := create_test_profile();
    _template_id UUID := create_test_template(_user_id => _user_id);
    _earlier     UUID := create_test_template(_user_id => _user_id);
BEGIN
    DELETE FROM templates WHERE id = _earlier;
    DELETE FROM profiles WHERE id = _user_id;
    RETURN NEXT is(
            (SELECT count(*) FROM archive.deleted_templates WHERE id IN (_template_id, _earlier)),
            0::bigint,
            'an account that is gone leaves nothing remembered'
        );
END
$$ LANGUAGE plpgsql;

SELECT * FROM runtests();

ROLLBACK;
