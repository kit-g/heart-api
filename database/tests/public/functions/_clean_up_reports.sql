BEGIN;

CREATE OR REPLACE FUNCTION test__clean_up_reports() RETURNS SETOF TEXT AS
$$
DECLARE
    _who TEXT := 'reporter-' || uuidv7();
BEGIN
    RETURN NEXT has_function('public'::name, '_clean_up_reports'::name);
    RETURN NEXT is((SELECT count(*) FROM reports WHERE reporter_id = _who), 0::bigint, 'none yet');

    INSERT INTO reports (reporter_id, reported_id, reason, sealed, verified, created_at, closed_at)
    VALUES (_who, 'x', 'old_closed', 's', true, now() - INTERVAL '2 years', now() - INTERVAL '91 days'),
           (_who, 'x', 'new_closed', 's', true, now() - INTERVAL '2 years', now() - INTERVAL '89 days'),
           (_who, 'x', 'old_open', 's', true, now() - INTERVAL '366 days', NULL),
           (_who, 'x', 'new_open', 's', true, now() - INTERVAL '364 days', NULL);
    PERFORM _clean_up_reports();

    RETURN NEXT is(
        (SELECT array_agg(reason ORDER BY reason) FROM reports WHERE reporter_id = _who),
        ARRAY ['new_closed', 'new_open'],
        'what has passed its deadline goes'
    );
END
$$ LANGUAGE plpgsql;

SELECT * FROM runtests();

ROLLBACK;
