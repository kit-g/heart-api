-- The per-user ceiling on custom exercises: an INSERT into exercises that
-- would push a user past 2000 owned rows is refused wholesale. Global
-- library rows (user_id IS NULL) are neither counted nor blocked — content
-- syncs must never trip this.

BEGIN;

CREATE OR REPLACE FUNCTION test__custom_exercises_cap_signature() RETURNS SETOF TEXT AS
$$
BEGIN
    RETURN NEXT has_function('public'::name, 'assert_custom_exercises_capped'::name);
    RETURN NEXT function_returns('public'::name, 'assert_custom_exercises_capped'::name, 'trigger');
    RETURN NEXT function_lang_is('public'::name, 'assert_custom_exercises_capped'::name, 'plpgsql'::name);
    RETURN NEXT has_trigger('public'::name, 'exercises'::name, 'exercises_custom_cap'::name);
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test__custom_exercises_cap_enforced() RETURNS SETOF TEXT AS
$$
DECLARE
    _user_id  TEXT;
    _other_id TEXT;
BEGIN
    _user_id := create_test_profile();
    _other_id := create_test_profile();

    RETURN NEXT is(
        (SELECT count(*) FROM exercises WHERE user_id = _user_id),
        0::bigint,
        'no customs yet'
    );

    RETURN NEXT lives_ok(
        format(
            'INSERT INTO exercises (name, category, target, user_id) SELECT ''cap test '' || n, ''Barbell'', ''Other'', %L FROM generate_series(1, 2000) n',
            _user_id
        ),
        'a user can fill to exactly the cap'
    );

    RETURN NEXT throws_ok(
        format(
            'INSERT INTO exercises (name, category, target, user_id) VALUES (''one too many'', ''Barbell'', ''Other'', %L)',
            _user_id
        ),
        '23514',
        format('custom exercises cap (2000) exceeded for user %s', _user_id),
        'the custom crossing the cap is refused'
    );

    RETURN NEXT lives_ok(
        format(
            'INSERT INTO exercises (name, category, target, user_id) VALUES (''fresh account custom'', ''Barbell'', ''Other'', %L)',
            _other_id
        ),
        'one user at the cap does not block another'
    );

    RETURN NEXT lives_ok(
        'INSERT INTO exercises (name, category, target) VALUES (''global cap-test row'', ''Barbell'', ''Other'')',
        'global library rows are exempt'
    );

    DELETE FROM exercises WHERE name = 'global cap-test row' AND user_id IS NULL;
END
$$ LANGUAGE plpgsql;

SELECT * FROM runtests();

ROLLBACK;
