-- Template folders: a flat, per-user grouping for templates. A coach with a roster wants their
-- masters filed by student or by block ("Alice", "Off-season", "Beginners"); an individual wants
-- theirs filed by split. Both are the same thing — a named bucket the owner arranges — so a folder
-- carries no coaching semantics of its own and is never shared as an object. Sharing a folder is
-- shorthand for sharing every template in it, and the student's copies land unfoldered for them to
-- file themselves.
--
-- Unlike most tables here this one does NOT lead with DROP: it hangs a column off the live
-- `templates` table, so the migration is written to be re-runnable without discarding anyone's
-- filing.

CREATE TABLE IF NOT EXISTS template_folders
(
    id          UUID                 DEFAULT uuidv7() PRIMARY KEY,
    user_id     TEXT        NOT NULL REFERENCES profiles (id) ON DELETE CASCADE,
    name        TEXT        NOT NULL,
    order_index INTEGER     NOT NULL DEFAULT 0,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT template_folders_name_check CHECK (length(trim(name)) > 0),
    -- the target of the composite FK below; redundant as a key, load-bearing as a constraint
    CONSTRAINT template_folders_id_user_key UNIQUE (id, user_id)
);

-- Two folders that differ only in case read as duplicates to the person scrolling the list.
CREATE UNIQUE INDEX IF NOT EXISTS template_folders_user_name_idx ON template_folders (user_id, lower(name));

ALTER TABLE templates
    DROP COLUMN IF EXISTS folder_id,
    ADD COLUMN IF NOT EXISTS folder_id UUID;

-- Composite, not a plain FK to template_folders(id): pairing folder_id with user_id makes it
-- structurally impossible to file a template into someone else's folder, which a single-column FK
-- would happily allow. SET NULL names its column (PG 15+) because templates.user_id is NOT NULL and
-- an unqualified SET NULL would try to null it too.
ALTER TABLE templates
    DROP CONSTRAINT IF EXISTS templates_folder_fk;
ALTER TABLE templates
    ADD CONSTRAINT templates_folder_fk
        FOREIGN KEY (folder_id, user_id) REFERENCES template_folders (id, user_id)
            ON DELETE SET NULL (folder_id);

CREATE INDEX IF NOT EXISTS templates_folder_id_idx ON templates (folder_id) WHERE folder_id IS NOT NULL;

COMMENT ON TABLE template_folders IS 'Flat, per-user grouping for templates; a name and an order, no coaching semantics';
COMMENT ON COLUMN template_folders.name IS 'Owner-supplied label, unique per user case-insensitively';
COMMENT ON COLUMN template_folders.order_index IS 'Owner-arranged position in the folder list; ties break on name';
COMMENT ON COLUMN templates.folder_id IS
    'Folder the owner filed this template under; NULL means unfiled. Deleting a folder unfiles its templates rather than destroying them';
COMMENT ON CONSTRAINT template_folders_id_user_key ON template_folders IS
    'Composite key so templates_folder_fk can pin a folder to the same owner as the template';
COMMENT ON CONSTRAINT templates_folder_fk ON templates IS
    'A template can only be filed into a folder belonging to the same user';
