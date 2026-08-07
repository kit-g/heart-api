-- Range checks on measurements, indexes for secondary FK delete paths, and
-- archive fixes.
--
-- exercise_sets / template_exercise_sets have carried CHECK (set_order >= 0)
-- since the initial schema, but weight / reps / duration / distance had no
-- range checks at all: weight = -50 inserted fine. NOT VALID so this cannot
-- fail on legacy rows at deploy time — new writes are checked immediately;
-- run ALTER TABLE … VALIDATE CONSTRAINT … once the data is confirmed clean.

ALTER TABLE exercise_sets
    DROP CONSTRAINT IF EXISTS exercise_sets_weight_nonnegative_check,
    DROP CONSTRAINT IF EXISTS exercise_sets_reps_nonnegative_check,
    DROP CONSTRAINT IF EXISTS exercise_sets_duration_nonnegative_check,
    DROP CONSTRAINT IF EXISTS exercise_sets_distance_nonnegative_check;

ALTER TABLE exercise_sets
    ADD CONSTRAINT exercise_sets_weight_nonnegative_check CHECK (weight IS NULL OR weight >= 0) NOT VALID,
    ADD CONSTRAINT exercise_sets_reps_nonnegative_check CHECK (reps IS NULL OR reps >= 0) NOT VALID,
    ADD CONSTRAINT exercise_sets_duration_nonnegative_check CHECK (duration IS NULL OR duration >= 0) NOT VALID,
    ADD CONSTRAINT exercise_sets_distance_nonnegative_check CHECK (distance IS NULL OR distance >= 0) NOT VALID;

ALTER TABLE template_exercise_sets
    DROP CONSTRAINT IF EXISTS template_exercise_sets_weight_nonnegative_check,
    DROP CONSTRAINT IF EXISTS template_exercise_sets_reps_nonnegative_check,
    DROP CONSTRAINT IF EXISTS template_exercise_sets_duration_nonnegative_check,
    DROP CONSTRAINT IF EXISTS template_exercise_sets_distance_nonnegative_check;

ALTER TABLE template_exercise_sets
    ADD CONSTRAINT template_exercise_sets_weight_nonnegative_check CHECK (weight IS NULL OR weight >= 0) NOT VALID,
    ADD CONSTRAINT template_exercise_sets_reps_nonnegative_check CHECK (reps IS NULL OR reps >= 0) NOT VALID,
    ADD CONSTRAINT template_exercise_sets_duration_nonnegative_check CHECK (duration IS NULL OR duration >= 0) NOT VALID,
    ADD CONSTRAINT template_exercise_sets_distance_nonnegative_check CHECK (distance IS NULL OR distance >= 0) NOT VALID;

-- Secondary FK columns with no index: every ON DELETE SET NULL / CASCADE on
-- these paths scanned the referencing table. Partial where the column is
-- nullable and mostly null.

CREATE INDEX IF NOT EXISTS templates_source_template_id_idx
    ON templates (source_template_id) WHERE source_template_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS templates_assigned_by_idx
    ON templates (assigned_by) WHERE assigned_by IS NOT NULL;
CREATE INDEX IF NOT EXISTS connections_status_by_idx
    ON connections (status_by) WHERE status_by IS NOT NULL;
CREATE INDEX IF NOT EXISTS template_shares_student_id_idx ON template_shares (student_id);
CREATE INDEX IF NOT EXISTS template_shares_master_template_id_idx ON template_shares (master_template_id);
CREATE INDEX IF NOT EXISTS template_shares_student_template_id_idx ON template_shares (student_template_id);

COMMENT ON INDEX templates_source_template_id_idx IS 'ON DELETE SET NULL path when a shared source template is deleted';
COMMENT ON INDEX templates_assigned_by_idx IS 'ON DELETE SET NULL path when an assigning coach''s profile is deleted';
COMMENT ON INDEX connections_status_by_idx IS 'ON DELETE SET NULL path when the status-setting profile is deleted';
COMMENT ON INDEX template_shares_student_id_idx IS 'Cascade path when a student profile is deleted';
COMMENT ON INDEX template_shares_master_template_id_idx IS 'Cascade path when a master template is deleted; the unique index leads on coach_id';
COMMENT ON INDEX template_shares_student_template_id_idx IS 'Cascade path when a student''s copy of a template is deleted';

-- archive.deleted_workouts: per-user deleted history reads had no index, and
-- created_at was nullable although the source column (workouts.created_at,
-- copied by _archive_workout) never is. Backfill defensively before
-- tightening — deleted_at is NOT NULL.

CREATE INDEX IF NOT EXISTS deleted_workouts_user_id_deleted_at_idx
    ON archive.deleted_workouts (user_id, deleted_at DESC);

COMMENT ON INDEX archive.deleted_workouts_user_id_deleted_at_idx IS 'Per-user deleted history, newest deletions first';

UPDATE archive.deleted_workouts SET created_at = deleted_at WHERE created_at IS NULL;
ALTER TABLE archive.deleted_workouts ALTER COLUMN created_at SET NOT NULL;

-- The lone prefix-named index in a suffix-_idx schema.
ALTER INDEX IF EXISTS idx_connections_target_id RENAME TO connections_target_id_idx;
