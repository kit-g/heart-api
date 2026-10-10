-- What another app calls an exercise in each language its export can be
-- written in, resolved to the English name the same export carries in
-- English: the lookup applied to an imported exercise title before it is
-- matched against the library. Reference content, not user data: written
-- only by its loader from the source app's own catalog, which stays outside
-- this repository.
DROP TABLE IF EXISTS import_names;
CREATE TABLE IF NOT EXISTS import_names
(
    source TEXT NOT NULL,
    title  TEXT NOT NULL,
    name   TEXT NOT NULL,
    CONSTRAINT import_names_source_check CHECK (source IN ('strong', 'hevy'))
);

-- one row per title per app, whatever its case: an export's spelling is
-- looked up case-insensitively
CREATE UNIQUE INDEX IF NOT EXISTS import_names_source_title_idx
    ON import_names (source, lower(title));

COMMENT ON TABLE import_names IS
    'An exporting app''s exercise titles in every language it writes, each resolved to its English title. Reference content, written only by the loader.';
COMMENT ON COLUMN import_names.source IS
    'The exporting app, as the import accepts it (strong, hevy).';
COMMENT ON COLUMN import_names.title IS
    'A title exactly as that app''s export writes it in some language.';
COMMENT ON COLUMN import_names.name IS
    'The English title of the same exercise, which the library''s names and aliases are matched against.';
COMMENT ON CONSTRAINT import_names_source_check ON import_names IS
    'Only the apps the import reads.';
COMMENT ON INDEX import_names_source_title_idx IS
    'One resolution per title per app, case-insensitively, since lookups are.';
