BEGIN;

CREATE OR REPLACE FUNCTION test__clip_pauses_signature() RETURNS SETOF TEXT AS
$$
BEGIN
    RETURN NEXT has_function('public'::name, '_clip_pauses'::name, ARRAY ['jsonb', 'timestamp with time zone', 'timestamp with time zone']);
    RETURN NEXT function_returns('public'::name, '_clip_pauses'::name, ARRAY ['jsonb', 'timestamp with time zone', 'timestamp with time zone'], 'jsonb');
    RETURN NEXT function_lang_is('public'::name, '_clip_pauses'::name, ARRAY ['jsonb', 'timestamp with time zone', 'timestamp with time zone'], 'sql'::name);
    RETURN NEXT volatility_is('public'::name, '_clip_pauses'::name, ARRAY ['jsonb', 'timestamp with time zone', 'timestamp with time zone'], 'immutable');
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test__clip_pauses_cuts_to_the_window() RETURNS SETOF TEXT AS
$$
DECLARE
    _pauses CONSTANT JSONB := '[{"start": "2026-10-03T18:05:00Z", "end": "2026-10-03T18:10:00Z"},
                                {"start": "2026-10-03T18:30:00Z", "end": "2026-10-03T18:40:00Z"},
                                {"start": "2026-10-03T18:50:00Z", "end": "2026-10-03T18:55:00Z"}]';
BEGIN
    RETURN NEXT is(_clip_pauses('[]', '2026-10-03T18:00:00Z', '2026-10-03T19:00:00Z'), '[]'::jsonb, 'no pauses stay none');
    RETURN NEXT is(
            _clip_pauses(_pauses, '2026-10-03T18:00:00Z', '2026-10-03T19:00:00Z'),
            _pauses,
            'pauses already inside are kept exactly as written'
        );
    RETURN NEXT is(
            _clip_pauses(_pauses, '2026-10-03T18:00:00Z', NULL),
            _pauses,
            'an unfinished workout clips by its start only'
        );
    RETURN NEXT is(
            _clip_pauses(_pauses, '2026-10-03T18:07:00Z', '2026-10-03T18:35:00Z'),
            '[{"start": "2026-10-03T18:07:00.000000Z", "end": "2026-10-03T18:10:00.000000Z"},
              {"start": "2026-10-03T18:30:00.000000Z", "end": "2026-10-03T18:35:00.000000Z"}]'::jsonb,
            'crossing pauses are shortened to the new ends, and those outside dropped'
        );
    RETURN NEXT is(
            _clip_pauses(_pauses, '2026-10-03T18:00:00Z', '2026-10-03T18:30:00Z'),
            '[{"start": "2026-10-03T18:05:00Z", "end": "2026-10-03T18:10:00Z"}]'::jsonb,
            'a pause the new end merely touches is dropped'
        );
    RETURN NEXT ok(
            _pauses_fit(_clip_pauses(_pauses, '2026-10-03T18:07:00Z', '2026-10-03T18:35:00Z'),
                        '2026-10-03T18:07:00Z', '2026-10-03T18:35:00Z'),
            'what it returns fits the window it was cut to'
        );
END
$$ LANGUAGE plpgsql;

SELECT * FROM runtests();

ROLLBACK;
