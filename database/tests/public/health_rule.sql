-- The device-only health rule (CLAUDE.md) as a schema invariant: no column in
-- any schema is named for a health reading. Names compare case- and
-- separator-blind. The same list guards request bodies in
-- api/lib/core/request.dart; keep the two in step.
BEGIN;

SELECT plan(1);

SELECT is_empty(
               $$
               SELECT table_schema || '.' || table_name || '.' || column_name
               FROM information_schema.columns
               CROSS JOIN LATERAL (SELECT regexp_replace(lower(column_name), '[^a-z0-9]', '', 'g') AS normalized) n
               WHERE table_schema NOT IN ('pg_catalog', 'information_schema')
                 AND (
                   n.normalized ~ '(heartrate|hrv|sleep|bodymass|bodyweight|bodyfat|activeenergy|restingenergy|basalenergy|stepcount|oxygensaturation|spo2|vo2max|respiratoryrate|bloodpressure|bloodglucose)'
                   OR n.normalized = 'steps'
                 )
               $$,
               'no column is named for a health reading'
       );

SELECT * FROM finish();
ROLLBACK;
