BEGIN;

SELECT plan(10);

SELECT has_table('public'::name, 'program_histories'::name);

SELECT columns_are(
               'public',
               'program_histories',
               ARRAY [
                   'program_id',
                   'user_id',
                   'changed_xid'
                   ]
       );

SELECT has_pk('public'::name, 'program_histories'::name);
SELECT col_is_pk('public'::name, 'program_histories'::name, 'program_id'::name);

SELECT col_type_is('public'::name, 'program_histories'::name, 'changed_xid'::name, 'xid8'::name);

SELECT col_not_null('public'::name, 'program_histories'::name, 'user_id'::name);
SELECT col_not_null('public'::name, 'program_histories'::name, 'changed_xid'::name);

SELECT col_default_is('public', 'program_histories', 'changed_xid', 'pg_current_xact_id()', 'stamped by the transaction that writes it');

SELECT fk_ok(
               'public', 'program_histories', ARRAY ['program_id', 'user_id'],
               'public', 'programs', ARRAY ['id', 'user_id']
       );

SELECT has_index('public'::name, 'program_histories'::name, 'program_histories_user_changed_idx'::name);

SELECT * FROM finish();

ROLLBACK;
