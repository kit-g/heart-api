BEGIN;

SELECT plan(21);

SELECT has_table('public'::name, 'templates'::name);

SELECT columns_are(
               'public',
               'templates',
               ARRAY [
                   'id',
                   'user_id',
                   'name',
                   'order_index',
                   'source_template_id',
                   'assigned_by',
                   'sync_enabled',
                   'created_at'
                   ]
       );

SELECT col_type_is('public'::name, 'templates'::name, 'id'::name, 'uuid'::name);
SELECT col_type_is('public'::name, 'templates'::name, 'user_id'::name, 'text'::name);
SELECT col_type_is('public'::name, 'templates'::name, 'name'::name, 'text'::name);
SELECT col_type_is('public'::name, 'templates'::name, 'order_index'::name, 'integer'::name);
SELECT col_type_is('public'::name, 'templates'::name, 'source_template_id'::name, 'uuid'::name);
SELECT col_type_is('public'::name, 'templates'::name, 'assigned_by'::name, 'text'::name);
SELECT col_type_is('public'::name, 'templates'::name, 'sync_enabled'::name, 'boolean'::name);
SELECT col_type_is('public'::name, 'templates'::name, 'created_at'::name, 'timestamp with time zone'::name);

SELECT has_pk('public'::name, 'templates'::name, 'templates has a primary key');
SELECT col_is_pk('public'::name, 'templates'::name, 'id'::name, 'id is the primary key');

SELECT col_not_null('public'::name, 'templates'::name, 'id'::name);
SELECT col_not_null('public'::name, 'templates'::name, 'user_id'::name);
SELECT col_not_null('public'::name, 'templates'::name, 'order_index'::name);

SELECT col_default_is('public', 'templates', 'id', 'uuidv7()', 'id default is uuidv7()');
SELECT col_default_is('public', 'templates', 'order_index', '0', 'order_index default is 0');
SELECT col_default_is('public', 'templates', 'created_at', 'now()', 'created_at default is now()');

SELECT fk_ok('public', 'templates', 'user_id', 'public', 'profiles', 'id');
SELECT fk_ok('public', 'templates', 'source_template_id', 'public', 'templates', 'id');
SELECT fk_ok('public', 'templates', 'assigned_by', 'public', 'profiles', 'id');

SELECT * FROM finish();

ROLLBACK;
