-- A library program's copies, looked up by it alone: the SET NULL when it is
-- deleted, and who holds it. The unique key leads with the student, so it can't.

DROP INDEX IF EXISTS programs_library_program_idx;
CREATE INDEX IF NOT EXISTS programs_library_program_idx ON programs (library_program_id)
    WHERE library_program_id IS NOT NULL;

COMMENT ON INDEX programs_library_program_idx IS 'The SET NULL when a library program is deleted, and its holders';
