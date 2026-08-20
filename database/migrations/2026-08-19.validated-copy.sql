-- Surfaces the exercise library's per-locale `validated` flag (a human has
-- reviewed this copy) to the API, so the client can label machine-authored
-- copy — kit-g/heart-api: AI-written instructions get a spark icon in the
-- exercise library, in the spirit of being explicit about their provenance.
--
-- Nullable on purpose: NULL is "no stance" — user-created exercises carry
-- their owner's copy and the sync never touches them; FALSE is copy nobody
-- has reviewed (machine-authored); TRUE is human-reviewed. Only
-- scripts/library_locales.py writes it, from i18n.<locale>.validated in
-- content/exercise_library.yml, so the column is reproducible via db-seed
-- and safe to rebuild.

ALTER TABLE exercises
    DROP COLUMN IF EXISTS validated,
    ADD COLUMN IF NOT EXISTS validated BOOLEAN;

COMMENT ON COLUMN exercises.validated IS
    'Whether a human has reviewed this exercise''s fallback-locale copy. NULL = not library-managed (user-created exercises); FALSE = machine-authored, unreviewed; TRUE = human-reviewed. Written only by the library sync (scripts/library_locales.py).';

ALTER TABLE exercise_translations
    DROP COLUMN IF EXISTS validated,
    ADD COLUMN IF NOT EXISTS validated BOOLEAN;

COMMENT ON COLUMN exercise_translations.validated IS
    'Whether a human has reviewed this locale''s copy — the per-locale twin of exercises.validated, following the same NULL/FALSE/TRUE semantics.';
