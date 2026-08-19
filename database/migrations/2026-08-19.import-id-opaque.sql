-- Two guards on bulk-imported workouts, from the same ticket (#56):
--
-- 1. import_id became opaque: the source prefix survives for targeted cleanup
--    ('strong:%'), but the rest is now a sha256-derived token instead of raw
--    '<date>#<workout name>' — a dedup key ends up in URLs and logs, and its
--    old shape leaked user content and invited parsing. Comment-only change;
--    the column and its partial unique index are untouched.
--
-- 2. A hard ceiling on imported workouts per user, enforced by the database
--    itself so no write path — present or future — can grow an account's
--    imported history without bound. The API already truncates a single batch
--    to its most recent 10k workouts; this backstops accumulation across
--    requests (scripted re-imports of disjoint synthetic files).
--    Statement-level with a transition table: one cheap check per INSERT
--    statement, and the count only runs when the statement actually wrote
--    imported rows. App-created workouts (import_id IS NULL) are never
--    counted or blocked.

COMMENT ON COLUMN workouts.import_id IS
    'Deterministic opaque identity for bulk-imported workouts (''<source>:<16 hex of sha256 over the source row>''); unique per user, NULL for app-created workouts';

CREATE OR REPLACE FUNCTION assert_imported_workouts_capped() RETURNS trigger
    LANGUAGE plpgsql
AS
$$
DECLARE
    _offender TEXT;
BEGIN
    SELECT n.user_id
    INTO _offender
    FROM (
        SELECT DISTINCT user_id
        FROM new_rows
        WHERE import_id IS NOT NULL
    ) n
    WHERE (
        SELECT count(*)
        FROM workouts w
        WHERE w.user_id = n.user_id
          AND w.import_id IS NOT NULL
    ) > 20000
    LIMIT 1;
    IF _offender IS NOT NULL THEN
        RAISE EXCEPTION 'imported workouts cap (20000) exceeded for user %', _offender
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NULL;
END
$$;

COMMENT ON FUNCTION assert_imported_workouts_capped() IS
    'Statement-level AFTER INSERT guard on workouts: refuses the write when a user''s rows with import_id IS NOT NULL would exceed 20000. Raises check_violation (23514); the API maps it to a 400.';

DROP TRIGGER IF EXISTS workouts_imported_cap ON workouts;
CREATE TRIGGER workouts_imported_cap
    AFTER INSERT
    ON workouts
    REFERENCING NEW TABLE AS new_rows
    FOR EACH STATEMENT
EXECUTE FUNCTION assert_imported_workouts_capped();

COMMENT ON TRIGGER workouts_imported_cap ON workouts IS
    'Per-user ceiling of 20000 bulk-imported workouts; app-created workouts (import_id IS NULL) are unaffected';
