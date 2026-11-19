-- The transaction that last created a program or changed its history (its
-- steps and bases). Transaction ids belong to one cluster: a move to another one
-- re-stamps the column (docs/2026-09-23.developer-api.md, Moving the database).

DROP TABLE IF EXISTS program_histories;

CREATE TABLE IF NOT EXISTS program_histories
(
    program_id  UUID PRIMARY KEY,
    user_id     TEXT NOT NULL,
    changed_xid XID8 NOT NULL DEFAULT pg_current_xact_id(),

    CONSTRAINT program_histories_program_fk
        FOREIGN KEY (program_id, user_id) REFERENCES programs (id, user_id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS program_histories_user_changed_idx ON program_histories (user_id, changed_xid, program_id);

COMMENT ON TABLE program_histories IS
    'One row per program: the transaction that last created it or changed its steps or bases';
COMMENT ON COLUMN program_histories.program_id IS 'The program, one row each';
COMMENT ON COLUMN program_histories.user_id IS 'The program''s owner, part of the key that reaches it';
COMMENT ON COLUMN program_histories.changed_xid IS
    'The transaction that created the program, or last added, changed or removed one of its steps or bases';
COMMENT ON CONSTRAINT program_histories_program_fk ON program_histories IS
    'Goes with its program';
COMMENT ON INDEX program_histories_user_changed_idx IS
    'One account''s programs in the order their history changes finished, by transaction';

-- Stamps the named programs with this transaction. A program being deleted
-- takes its row with it and is left unstamped.
CREATE OR REPLACE FUNCTION _stamp_program_histories(_program_ids UUID[]) RETURNS VOID
    LANGUAGE sql
AS
$$
INSERT INTO program_histories (program_id, user_id)
SELECT id, user_id
FROM programs
WHERE id = ANY (_program_ids)
ON CONFLICT (program_id) DO UPDATE
    SET changed_xid = pg_current_xact_id()
    WHERE program_histories.changed_xid <> pg_current_xact_id()
$$;

COMMENT ON FUNCTION _stamp_program_histories(UUID[]) IS
    'Stamps each named program that still exists with this transaction';

-- Statement-level, so a bulk change stamps each program once. A trigger with
-- transition tables takes one event, and each branch reads only the tables its
-- event has. A row moved to another program stamps both.
CREATE OR REPLACE FUNCTION _stamp_program_histories_by_program_id() RETURNS trigger
    LANGUAGE plpgsql
AS
$$
BEGIN
    IF TG_OP = 'INSERT' THEN
        PERFORM _stamp_program_histories(ARRAY(SELECT DISTINCT program_id FROM new_rows));
    ELSIF TG_OP = 'UPDATE' THEN
        PERFORM _stamp_program_histories(
            ARRAY(
                SELECT program_id FROM old_rows
                UNION
                SELECT program_id FROM new_rows
            )
        );
    ELSE
        PERFORM _stamp_program_histories(ARRAY(SELECT DISTINCT program_id FROM old_rows));
    END IF;
    RETURN NULL;
END
$$;

COMMENT ON FUNCTION _stamp_program_histories_by_program_id() IS
    'AFTER each statement on program_actions or program_bases: stamps the programs it touched';

-- A program created stamps itself, so one deleted and created again under its
-- id reads as changed, with whatever history it has now.
CREATE OR REPLACE FUNCTION _stamp_program_histories_by_id() RETURNS trigger
    LANGUAGE plpgsql
AS
$$
BEGIN
    PERFORM _stamp_program_histories(ARRAY(SELECT id FROM new_rows));
    RETURN NULL;
END
$$;

COMMENT ON FUNCTION _stamp_program_histories_by_id() IS
    'AFTER each statement inserting programs: stamps each new one';

DROP TRIGGER IF EXISTS programs_stamp_history ON programs;
CREATE TRIGGER programs_stamp_history
    AFTER INSERT
    ON programs
    REFERENCING NEW TABLE AS new_rows
    FOR EACH STATEMENT
EXECUTE FUNCTION _stamp_program_histories_by_id();

COMMENT ON TRIGGER programs_stamp_history ON programs IS 'A program created, or created again under its id';

DROP TRIGGER IF EXISTS program_actions_stamp_insert ON program_actions;
CREATE TRIGGER program_actions_stamp_insert
    AFTER INSERT
    ON program_actions
    REFERENCING NEW TABLE AS new_rows
    FOR EACH STATEMENT
EXECUTE FUNCTION _stamp_program_histories_by_program_id();

DROP TRIGGER IF EXISTS program_actions_stamp_update ON program_actions;
CREATE TRIGGER program_actions_stamp_update
    AFTER UPDATE
    ON program_actions
    REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows
    FOR EACH STATEMENT
EXECUTE FUNCTION _stamp_program_histories_by_program_id();

DROP TRIGGER IF EXISTS program_actions_stamp_delete ON program_actions;
CREATE TRIGGER program_actions_stamp_delete
    AFTER DELETE
    ON program_actions
    REFERENCING OLD TABLE AS old_rows
    FOR EACH STATEMENT
EXECUTE FUNCTION _stamp_program_histories_by_program_id();

DROP TRIGGER IF EXISTS program_bases_stamp_insert ON program_bases;
CREATE TRIGGER program_bases_stamp_insert
    AFTER INSERT
    ON program_bases
    REFERENCING NEW TABLE AS new_rows
    FOR EACH STATEMENT
EXECUTE FUNCTION _stamp_program_histories_by_program_id();

DROP TRIGGER IF EXISTS program_bases_stamp_update ON program_bases;
CREATE TRIGGER program_bases_stamp_update
    AFTER UPDATE
    ON program_bases
    REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows
    FOR EACH STATEMENT
EXECUTE FUNCTION _stamp_program_histories_by_program_id();

DROP TRIGGER IF EXISTS program_bases_stamp_delete ON program_bases;
CREATE TRIGGER program_bases_stamp_delete
    AFTER DELETE
    ON program_bases
    REFERENCING OLD TABLE AS old_rows
    FOR EACH STATEMENT
EXECUTE FUNCTION _stamp_program_histories_by_program_id();

COMMENT ON TRIGGER program_actions_stamp_insert ON program_actions IS 'A step taken';
COMMENT ON TRIGGER program_actions_stamp_update ON program_actions IS 'A step moved, as when an exercise''s history moves';
COMMENT ON TRIGGER program_actions_stamp_delete ON program_actions IS 'A step undone, or gone with its workout';
COMMENT ON TRIGGER program_bases_stamp_insert ON program_bases IS 'A base moved';
COMMENT ON TRIGGER program_bases_stamp_update ON program_bases IS 'A base changed, as when an exercise''s history moves';
COMMENT ON TRIGGER program_bases_stamp_delete ON program_bases IS 'A base removed, or gone with its workout, step or exercise';

-- Every program there is, as changed now.
INSERT INTO program_histories (program_id, user_id)
SELECT id, user_id FROM programs
ON CONFLICT (program_id) DO NOTHING;
