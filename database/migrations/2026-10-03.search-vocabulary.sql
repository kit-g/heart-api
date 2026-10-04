-- Exercise search vocabulary, per locale:
--
--   exercises.aliases              other names the fallback-locale copy is
--   exercise_translations.aliases  searched by ('ohp', 'skull crusher'); NULL
--                                  is "none of its own", an empty array is
--                                  "deliberately none"
--   search_glossaries              one row per locale: words a lifter types
--                                  that stand for other words across the whole
--                                  library ('db' -> dumbbell, 'lats' -> a
--                                  muscle id prefix or group)
--
-- All of it is library content written only by the library sync, so a
-- re-run drops and rebuilds it; `make db-seed` reproduces it.

ALTER TABLE exercises
    DROP COLUMN IF EXISTS aliases,
    ADD COLUMN IF NOT EXISTS aliases TEXT[];

COMMENT ON COLUMN exercises.aliases IS
    'Other names the fallback-locale copy is searched by. NULL = none (user-created exercises, or library rows with none); written only by the library sync.';

ALTER TABLE exercise_translations
    DROP COLUMN IF EXISTS aliases,
    ADD COLUMN IF NOT EXISTS aliases TEXT[];

COMMENT ON COLUMN exercise_translations.aliases IS
    'Other names this locale''s copy is searched by. NULL = none of its own, read through the locale''s fallback like name; an empty array = deliberately none.';

DROP TABLE IF EXISTS search_glossaries;
CREATE TABLE IF NOT EXISTS search_glossaries
(
    locale TEXT PRIMARY KEY,
    terms  JSONB NOT NULL DEFAULT '{}',
    CONSTRAINT search_glossaries_terms_object CHECK (jsonb_typeof(terms) = 'object')
);

COMMENT ON TABLE search_glossaries IS
    'Per-locale exercise search vocabulary: abbreviations and gym muscle words that stand for other words across the whole library. Library content, written only by the library sync.';
COMMENT ON COLUMN search_glossaries.locale IS
    'Locale code, as in exercise_translations.locale.';
COMMENT ON COLUMN search_glossaries.terms IS
    'Map of word -> {"words": [phrases it stands for], "muscles": [muscle id prefixes or muscle groups it names]}, in its wire form.';
COMMENT ON CONSTRAINT search_glossaries_terms_object ON search_glossaries IS
    'terms is a map keyed by the word, never an array or scalar.';
