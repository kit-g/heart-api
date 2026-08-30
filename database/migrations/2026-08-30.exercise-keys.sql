-- Stable content keys for library exercises.
--
-- The English display name was the identity everywhere: the YAML map key, the
-- sync's conflict target, the app's wire reference, the asset pipeline's S3
-- keys. With the library localized, the name is copy — and copy must be
-- renamable without forking identity (the old sync archived the renamed row
-- and inserted a fresh one, splitting history). `key` is the kebab-case slug
-- (bench-press-barbell), minted once from the English name and never
-- re-derived: the sync (scripts/library_locales.py) conflicts on it, so a
-- rename updates the row in place — same uuid, history and translations
-- intact. User-created exercises keep key NULL: their identity is the uuid
-- and their owners rename them freely.

ALTER TABLE exercises
    DROP COLUMN IF EXISTS "key",
    ADD COLUMN IF NOT EXISTS "key" TEXT;

-- Backfill mirrors the slugs content/exercise_library.yml is keyed by:
-- lowercase, non-alphanumeric runs collapsed to '-', edges trimmed. If this
-- expression ever drifted from the content keys, the next sync fails loudly
-- (key miss -> fresh insert -> 23505 on exercises_global_name_idx), never
-- silently.
UPDATE exercises
SET key = btrim(regexp_replace(lower(name), '[^a-z0-9]+', '-', 'g'), '-')
WHERE user_id IS NULL
  AND key IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS exercises_global_key_idx ON exercises (key) WHERE user_id IS NULL;

ALTER TABLE exercises
    DROP CONSTRAINT IF EXISTS exercises_global_key_chk;
ALTER TABLE exercises
    ADD CONSTRAINT exercises_global_key_chk CHECK (user_id IS NOT NULL OR key IS NOT NULL);

COMMENT ON COLUMN exercises.key IS
    'Stable content identity for library exercises (user_id IS NULL): the kebab-case slug the content repo keys this exercise by. Minted once, never re-derived from the name — the name is renamable display copy. NULL for user-created exercises, whose identity is the uuid.';
COMMENT ON CONSTRAINT exercises_global_key_chk ON exercises IS
    'Every library exercise must carry its content key; user-created rows never do.';
