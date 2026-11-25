BEGIN;

SELECT plan(11);

SELECT has_table('archive'::name, 'deleted_templates'::name);

SELECT columns_are(
               'archive',
               'deleted_templates',
               ARRAY [
                   'user_id',
                   'id',
                   'deleted_at'
                   ]
       );

SELECT col_type_is('archive'::name, 'deleted_templates'::name, 'user_id'::name, 'text'::name);
SELECT col_type_is('archive'::name, 'deleted_templates'::name, 'id'::name, 'uuid'::name);
SELECT col_type_is('archive'::name, 'deleted_templates'::name, 'deleted_at'::name, 'timestamp with time zone'::name);

SELECT col_is_pk('archive'::name, 'deleted_templates'::name, ARRAY ['user_id', 'id']::name[]);

SELECT col_not_null('archive'::name, 'deleted_templates'::name, 'user_id'::name);
SELECT col_not_null('archive'::name, 'deleted_templates'::name, 'id'::name);
SELECT col_not_null('archive'::name, 'deleted_templates'::name, 'deleted_at'::name);

SELECT col_default_is('archive', 'deleted_templates', 'deleted_at', 'now()', 'stamped when deleted');

SELECT fk_ok('archive', 'deleted_templates', 'user_id', 'public', 'profiles', 'id');

SELECT * FROM finish();

ROLLBACK;
