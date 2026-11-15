BEGIN;

CREATE OR REPLACE FUNCTION test__exercise_name_signature() RETURNS SETOF TEXT AS
$$
BEGIN
    RETURN NEXT has_function('public'::name, '_exercise_name'::name, ARRAY ['uuid', 'text', 'text']);
    RETURN NEXT function_returns('public'::name, '_exercise_name'::name, ARRAY ['uuid', 'text', 'text'], 'text');
    RETURN NEXT function_lang_is('public'::name, '_exercise_name'::name, ARRAY ['uuid', 'text', 'text'], 'sql'::name);
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test__exercise_name_follows_the_locale() RETURNS SETOF TEXT AS
$$
DECLARE
    _squat UUID;
BEGIN
    _squat := create_test_exercise(_name => 'Squat (Barbell)');

    RETURN NEXT is(
        (SELECT count(*) FROM exercise_translations WHERE exercise_id = _squat), 0::bigint, 'no translations yet'
    );

    INSERT INTO exercise_translations (exercise_id, locale, name)
    VALUES (_squat, 'ru', 'Приседания (штанга)'),
           (_squat, 'es', 'Sentadilla (barra)'),
           (_squat, 'es_ES', 'Sentadilla (barra, ES)');

    RETURN NEXT is(_exercise_name(_squat, 'Squat (Barbell)', 'ru'), 'Приседания (штанга)', 'the locale''s own');
    RETURN NEXT is(_exercise_name(_squat, 'Squat (Barbell)', 'es_ES'), 'Sentadilla (barra, ES)', 'a regional one''s own');
    RETURN NEXT is(_exercise_name(_squat, 'Squat (Barbell)', 'es_MX'), 'Sentadilla (barra)', 'else the bare language''s');
    RETURN NEXT is(_exercise_name(_squat, 'Squat (Barbell)', 'fr'), 'Squat (Barbell)', 'else the name given');
    RETURN NEXT is(_exercise_name(_squat, 'Squat (Barbell)', NULL), 'Squat (Barbell)', 'no locale, the name given');
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test__exercise_name_in_a_workout() RETURNS SETOF TEXT AS
$$
DECLARE
    _user_id TEXT;
    _squat   UUID;
    _own     UUID;
    _w_id    UUID;
BEGIN
    _user_id := create_test_profile();
    _squat   := create_test_exercise(_name => 'Squat (Barbell)');
    _own     := create_test_exercise(_name => 'Жим Плужниковой', _user_id => _user_id);
    _w_id    := create_test_workout(_user_id => _user_id);

    RETURN NEXT is(
        (SELECT count(*) FROM workout_exercises WHERE workout_id = _w_id), 0::bigint, 'no exercises in the workout yet'
    );

    INSERT INTO exercise_translations (exercise_id, locale, name) VALUES (_squat, 'ru', 'Приседания (штанга)');
    PERFORM create_test_workout_exercise(_w_id, _squat, 0);
    PERFORM create_test_workout_exercise(_w_id, _own, 1);

    RETURN NEXT is(
        _workout_exercises(_w_id, 'ru') -> 0 -> 'exercise' ->> 'name', 'Приседания (штанга)', 'a library exercise in Russian'
    );
    RETURN NEXT is(
        _workout_exercises(_w_id, 'ru') -> 1 -> 'exercise' ->> 'name', 'Жим Плужниковой', 'an own exercise as its owner wrote it'
    );
    RETURN NEXT is(
        _workout_exercises(_w_id) -> 0 -> 'exercise' ->> 'name', 'Squat (Barbell)', 'without a locale, its own name'
    );
END
$$ LANGUAGE plpgsql;

SELECT * FROM runtests();

ROLLBACK;
