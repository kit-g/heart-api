-- Template folders: a flat, per-user grouping for templates. A coach with a roster wants their
-- masters filed by student or by block ("Alice", "Off-season", "Beginners"); an individual wants
-- theirs filed by split. Both are the same thing — a named bucket the owner arranges — so a folder
-- carries no coaching semantics of its own and is never shared as an object. Sharing a folder is
-- shorthand for sharing every template in it, and the student's copies land unfoldered for them to
-- file themselves.
--
-- Re-runnable like the rest: the column is dropped and re-added, and the FK dropped and re-added,
-- so applying this twice lands in the same place. Re-running discards filing, as a drop always
-- does — fine in dev, and the runner never re-applies a recorded migration anyway.

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

-- templates.order_index has been written since the initial schema and never read: `_listTemplates`
-- ordered by `id DESC` because that is what its keyset cursor walked, so the server sliced pages by
-- creation while the app displayed by the user's arrangement — a template dragged to the top could
-- land on page two. The listing now orders by (order_index, id) and pages on the same pair; this
-- index is what keeps that a range scan. templates had no index on user_id at all, so the previous
-- query was a seq scan plus a sort.
CREATE INDEX IF NOT EXISTS templates_user_order_idx ON templates (user_id, order_index, id);

-- No backfill of order_index: existing rows sit at the 0 default and the id tie-break resolves them
-- into creation order, which is the arrangement they have always effectively had. Ties are harmless
-- to the cursor because id is unique, so the pair is still a total order.

COMMENT ON INDEX templates_user_order_idx IS
    'Keyset support for _listTemplates: ORDER BY (order_index, id) scoped to one owner';
COMMENT ON TABLE template_folders IS 'Flat, per-user grouping for templates; a name and an order, no coaching semantics';
COMMENT ON COLUMN template_folders.name IS 'Owner-supplied label, unique per user case-insensitively';
COMMENT ON COLUMN template_folders.order_index IS 'Owner-arranged position in the folder list; ties break on name';
COMMENT ON COLUMN templates.folder_id IS
    'Folder the owner filed this template under; NULL means unfiled. Deleting a folder unfiles its templates rather than destroying them';
COMMENT ON CONSTRAINT template_folders_id_user_key ON template_folders IS
    'Composite key so templates_folder_fk can pin a folder to the same owner as the template';
COMMENT ON CONSTRAINT templates_folder_fk ON templates IS
    'A template can only be filed into a folder belonging to the same user';


-- Connections.
--
-- The table had no vocabulary constraints at all — `CHECK (length(status) > 0)` and nothing more —
-- so the only thing keeping role/status inside their enums was Dart, and Dart was coercing unknown
-- values rather than rejecting them (a typo'd role silently became PEER). It also had no record of
-- *who* set the current status, which meant a block could not be told from any other status: the
-- blocked party could lift it themselves.

-- A self-connection is meaningless and nothing ever guarded against one. Clear any before the
-- constraint lands.
DELETE FROM connections WHERE initiator_id = target_id;

ALTER TABLE connections
    DROP COLUMN IF EXISTS status_by,
    ADD COLUMN IF NOT EXISTS status_by TEXT REFERENCES profiles (id) ON DELETE SET NULL;

-- Best-effort backfill: for a pending row the initiator is provably the one who set it. For rows
-- already moved on, the initiator is a guess — acceptable only because it is impossible for a
-- blocked row to predate this migration in any deployed environment. If that stops being true, the
-- guess must be revisited before trusting status_by for authorisation.
UPDATE connections SET status_by = initiator_id WHERE status_by IS NULL;

ALTER TABLE connections
    DROP CONSTRAINT IF EXISTS connections_initiator_role_check,
    DROP CONSTRAINT IF EXISTS connections_target_role_check,
    DROP CONSTRAINT IF EXISTS connections_domain_check,
    DROP CONSTRAINT IF EXISTS connections_status_check,
    DROP CONSTRAINT IF EXISTS connections_no_self_check;

-- Roles and statuses are constrained; domain deliberately is not.
--
-- The code *branches* on role and status — reciprocal role mapping, the transition table, the
-- IN ('COACH', 'PEER') gate lists, every `status = 'active'` check — so those vocabularies are load
-- bearing and adding a value to either means touching code regardless. Pinning them here is free.
--
-- Domain is an opaque partition key. Not one gate filters on it; it exists so the same pair can hold
-- separate relationships for separate activities. Adding "cycling" is a product decision, and a
-- CHECK would turn it into a schema migration for no protection the input layer does not already
-- give: ConnectionDomain.fromString rejects unknown values before they reach the column.
ALTER TABLE connections
    ADD CONSTRAINT connections_initiator_role_check CHECK (initiator_role IN ('COACH', 'STUDENT', 'PEER')),
    ADD CONSTRAINT connections_target_role_check CHECK (target_role IN ('COACH', 'STUDENT', 'PEER')),
    ADD CONSTRAINT connections_status_check
        CHECK (status IN ('pending', 'active', 'declined', 'severed', 'blocked', 'paused')),
    ADD CONSTRAINT connections_no_self_check CHECK (initiator_id <> target_id);

CREATE INDEX IF NOT EXISTS connections_status_idx ON connections (status) WHERE status = 'active';

COMMENT ON COLUMN connections.status_by IS
    'Who last set status. Load-bearing for blocks: only the blocker may lift one, and only they may delete the row while it stands';
COMMENT ON CONSTRAINT connections_no_self_check ON connections IS
    'You cannot be your own coach, student or peer';
COMMENT ON CONSTRAINT connections_status_check ON connections IS
    'Mirrors ConnectionStatus; the transition rules between these live in Dart (canTransitionTo)';
