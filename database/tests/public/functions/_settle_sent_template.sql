BEGIN;

CREATE OR REPLACE FUNCTION test__settle_sent_template_signature() RETURNS SETOF TEXT AS
$$
BEGIN
    RETURN NEXT has_function('public'::name, '_settle_sent_template'::name);
    RETURN NEXT function_lang_is('public'::name, '_settle_sent_template'::name, 'plpgsql'::name);
    RETURN NEXT function_returns('public'::name, '_settle_sent_template'::name, 'trigger');
    RETURN NEXT trigger_is(
            'public'::name, 'workouts'::name,
            'workouts_settle_sent_template'::name,
            'public'::name, '_settle_sent_template'::name
        );
    RETURN NEXT has_function('public'::name, '_lock_template'::name, ARRAY ['uuid']);
    RETURN NEXT function_returns('public'::name, '_lock_template'::name, ARRAY ['uuid'], 'void');
    RETURN NEXT function_lang_is('public'::name, '_lock_template'::name, ARRAY ['uuid'], 'sql'::name);
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test__settle_sent_template_settles() RETURNS SETOF TEXT AS
$$
DECLARE
    _user_id TEXT := create_test_profile();
    _held    UUID := create_test_template(_user_id => _user_id);
    _gone    UUID := create_test_template(_user_id => _user_id);
    _theirs  UUID := create_test_template(_user_id => create_test_profile());
    _unheld  UUID := uuidv7();
    _workout UUID;
BEGIN
    RETURN NEXT is((SELECT count(*) FROM workouts WHERE user_id = _user_id), 0::bigint, 'no workouts yet');
    DELETE FROM templates WHERE id = _gone;
    _workout := create_test_workout(_user_id => _user_id);

    UPDATE workouts SET sent_template_id = _unheld WHERE id = _workout;
    RETURN NEXT is((SELECT sent_template_id FROM workouts WHERE id = _workout), _unheld, 'one not here is kept');

    UPDATE workouts SET sent_template_id = _gone WHERE id = _workout;
    RETURN NEXT is((SELECT sent_template_id FROM workouts WHERE id = _workout), NULL, 'a deleted one is dropped');

    UPDATE workouts SET sent_template_id = _theirs WHERE id = _workout;
    RETURN NEXT is(
            (SELECT coalesce(template_id, sent_template_id) FROM workouts WHERE id = _workout),
            NULL,
            'somebody else''s is dropped'
        );

    UPDATE workouts SET sent_template_id = _held WHERE id = _workout;
    RETURN NEXT results_eq(
            format('SELECT template_id, sent_template_id FROM workouts WHERE id = %L', _workout),
            format('VALUES (%L::uuid, NULL::uuid)', _held),
            'one here by now is linked'
        );

    UPDATE workouts SET template_id = NULL, logged_by = create_test_profile() WHERE id = _workout;
    UPDATE workouts SET sent_template_id = _unheld WHERE id = _workout;
    RETURN NEXT is((SELECT sent_template_id FROM workouts WHERE id = _workout), NULL, 'a workout someone entered keeps none');
END
$$ LANGUAGE plpgsql;

SELECT * FROM runtests();

ROLLBACK;
