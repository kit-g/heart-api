-- Bulk CSV import (Strong today, Hevy later): each imported workout carries a
-- deterministic identity derived from its source row (e.g.
-- 'strong:<date>#<workout name>'), so re-running the same export is a no-op
-- instead of a duplicated history. NULL for workouts created through the
-- app's own write path.

ALTER TABLE workouts
    ADD COLUMN IF NOT EXISTS import_id TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS workouts_user_import_id_idx
    ON workouts (user_id, import_id)
    WHERE import_id IS NOT NULL;

COMMENT ON COLUMN workouts.import_id IS
    'Deterministic source identity for bulk-imported workouts (''<source>:<date>#<workout name>''); unique per user, NULL for app-created workouts';
