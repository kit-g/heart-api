-- Health store representation per exercise, sourced from
-- content/exercise_library.yml and pushed by scripts/library_locales.py.
--
-- The `activity` key is the canonical, platform-neutral activity type a session
-- of this exercise is written to HealthKit / Health Connect as -- the label the
-- user reads in their Health app. The client maps it to each platform's enum
-- spelling; those spellings deliberately never appear here.
--
-- What this column deliberately is not:
--   * Not health data. It is reference content about an exercise, like
--     `movement` -- no user measurement ever lands in it, per the device-only
--     health rule (CLAUDE.md).
--   * Not required. NULL is the common case: the client derives the activity
--     from `category` (Cardio/Duration -> other, everything else -> strength),
--     the same fallback that covers user-created exercises, which have no
--     library annotation at all.
--   * Not session-level. cross_training / mixed_cardio describe a workout
--     mixing several exercises; the client derives them and they are never
--     stored per exercise.
--   * Not a policy. It records what the exercise is, never what a client
--     should do with it.

ALTER TABLE exercises
    DROP COLUMN IF EXISTS health,
    ADD COLUMN IF NOT EXISTS health JSONB;

COMMENT ON COLUMN exercises.health IS
    'Health store representation: {activity} -- the canonical camelCased activity type a session is written to HealthKit / Health Connect as. NULL when the client''s category fallback already labels the exercise correctly; reference content, never user health data';
