BEGIN;

SELECT plan(15);

SELECT has_table('public'::name, 'library_programs'::name);
SELECT columns_are('public', 'library_programs', ARRAY ['id', 'coach_id', 'name', 'version', 'created_at', 'updated_at']);
SELECT col_is_pk('public'::name, 'library_programs'::name, 'id'::name);
SELECT fk_ok('public', 'library_programs', 'coach_id', 'public', 'profiles', 'id');
SELECT col_default_is('public', 'library_programs', 'version', '1', 'starts at the first version');

SELECT has_table('public'::name, 'library_program_versions'::name);
SELECT col_is_pk('public'::name, 'library_program_versions'::name, ARRAY ['library_program_id', 'version'], 'one row per version');
SELECT fk_ok('public', 'library_program_versions', 'library_program_id', 'public', 'library_programs', 'id');

SELECT has_column('public', 'programs', 'coach_id', 'a copy knows its coach');
SELECT has_column('public', 'programs', 'connection_id', 'and the relationship');
SELECT has_column('public', 'programs', 'library_program_id', 'and where it came from');
SELECT has_column('public', 'programs', 'library_ids', 'and how its ids map');
SELECT has_column('public', 'programs', 'waiting_since', 'and whether it has started');
SELECT has_index('public'::name, 'programs'::name, 'programs_library_copy_key'::name);
SELECT has_column('public', 'invitations', 'library_program_id', 'an invitation can name a program');

SELECT * FROM finish();

ROLLBACK;
