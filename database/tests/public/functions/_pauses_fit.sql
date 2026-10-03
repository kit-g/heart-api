BEGIN;

CREATE OR REPLACE FUNCTION test__pauses_fit_signature() RETURNS SETOF TEXT AS
$$
BEGIN
    RETURN NEXT has_function('public'::name, '_pauses_fit'::name, ARRAY ['jsonb', 'timestamp with time zone', 'timestamp with time zone']);
    RETURN NEXT function_returns('public'::name, '_pauses_fit'::name, ARRAY ['jsonb', 'timestamp with time zone', 'timestamp with time zone'], 'boolean');
    RETURN NEXT function_lang_is('public'::name, '_pauses_fit'::name, ARRAY ['jsonb', 'timestamp with time zone', 'timestamp with time zone'], 'sql'::name);
    RETURN NEXT volatility_is('public'::name, '_pauses_fit'::name, ARRAY ['jsonb', 'timestamp with time zone', 'timestamp with time zone'], 'immutable');
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test__pauses_fit_accepts_ordered_pauses_inside() RETURNS SETOF TEXT AS
$$
BEGIN
    RETURN NEXT ok(_pauses_fit('[]', '2026-10-03T18:00:00Z', '2026-10-03T19:00:00Z'), 'no pauses fit');
    RETURN NEXT ok(_pauses_fit('[]', NULL, NULL), 'no pauses fit a workout without times');
    RETURN NEXT ok(
            _pauses_fit('[{"start": "2026-10-03T18:00:00Z", "end": "2026-10-03T18:10:00Z"},
                          {"start": "2026-10-03T18:10:00Z", "end": "2026-10-03T19:00:00Z"}]',
                        '2026-10-03T18:00:00Z', '2026-10-03T19:00:00Z'),
            'pauses may touch each other and either end'
        );
    RETURN NEXT ok(
            _pauses_fit('[{"start": "2026-10-03T20:10:00+02:00", "end": "2026-10-03T18:20:00Z"}]',
                        '2026-10-03T18:00:00Z', '2026-10-03T19:00:00Z'),
            'each instant is read with its own offset'
        );
    RETURN NEXT ok(
            _pauses_fit('[{"start": "2026-10-03T18:10:00Z", "end": "2026-10-03T18:20:00Z"}]',
                        '2026-10-03T18:00:00Z', NULL),
            'an unfinished workout bounds pauses by its start only'
        );
    RETURN NEXT ok(
            _pauses_fit((SELECT jsonb_agg(jsonb_build_object('start', t, 'end', t + interval '1 second'))
                         FROM generate_series(timestamptz '2026-10-03T18:00:00Z', timestamptz '2026-10-03T18:00:00Z' + interval '99 minutes', interval '1 minute') t),
                        '2026-10-03T18:00:00Z', '2026-10-03T20:00:00Z'),
            '100 pauses fit'
        );
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test__pauses_fit_rejects_bad_pauses() RETURNS SETOF TEXT AS
$$
BEGIN
    RETURN NEXT ok(NOT _pauses_fit('{}', NULL, NULL), 'not an array');
    RETURN NEXT ok(
            NOT _pauses_fit('[{"start": "2026-10-03T18:20:00Z", "end": "2026-10-03T18:10:00Z"}]', NULL, NULL),
            'a pause ending before it starts'
        );
    RETURN NEXT ok(
            NOT _pauses_fit('[{"start": "2026-10-03T18:10:00Z", "end": "2026-10-03T18:10:00Z"}]', NULL, NULL),
            'a pause with no length'
        );
    RETURN NEXT ok(
            NOT _pauses_fit('[{"start": "2026-10-03T18:10:00Z"}]', NULL, NULL),
            'a pause with no end'
        );
    RETURN NEXT ok(
            NOT _pauses_fit('[{"start": "2026-10-03T17:50:00Z", "end": "2026-10-03T18:10:00Z"}]',
                            '2026-10-03T18:00:00Z', NULL),
            'a pause starting before the workout'
        );
    RETURN NEXT ok(
            NOT _pauses_fit('[{"start": "2026-10-03T18:50:00Z", "end": "2026-10-03T19:10:00Z"}]',
                            '2026-10-03T18:00:00Z', '2026-10-03T19:00:00Z'),
            'a pause running past the end'
        );
    RETURN NEXT ok(
            NOT _pauses_fit('[{"start": "2026-10-03T18:30:00Z", "end": "2026-10-03T18:40:00Z"},
                              {"start": "2026-10-03T18:10:00Z", "end": "2026-10-03T18:35:00Z"}]', NULL, NULL),
            'overlapping pauses, whatever order they are listed in'
        );
    RETURN NEXT ok(
            NOT _pauses_fit((SELECT jsonb_agg(jsonb_build_object('start', t, 'end', t + interval '1 second'))
                             FROM generate_series(timestamptz '2026-10-03T18:00:00Z', timestamptz '2026-10-03T18:00:00Z' + interval '100 minutes', interval '1 minute') t),
                            NULL, NULL),
            '101 pauses'
        );
END
$$ LANGUAGE plpgsql;

SELECT * FROM runtests();

ROLLBACK;
