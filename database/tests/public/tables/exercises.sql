BEGIN;

SELECT plan(33);

SELECT has_table('public'::name, 'exercises'::name);

SELECT columns_are(
               'public',
               'exercises',
               ARRAY [
                   'id',
                   'name',
                   'category',
                   'target',
                   'instructions',
                   'asset',
                   'thumbnail',
                   'archived',
                   'muscles',
                   'movement',
                   'health',
                   'user_id',
                   'created_at'
                   ]
       );

SELECT col_type_is('public'::name, 'exercises'::name, 'id'::name, 'uuid'::name);
SELECT col_type_is('public'::name, 'exercises'::name, 'name'::name, 'text'::name);
SELECT col_type_is('public'::name, 'exercises'::name, 'category'::name, 'text'::name);
SELECT col_type_is('public'::name, 'exercises'::name, 'target'::name, 'text'::name);
SELECT col_type_is('public'::name, 'exercises'::name, 'instructions'::name, 'text'::name);
SELECT col_type_is('public'::name, 'exercises'::name, 'asset'::name, 'jsonb'::name);
SELECT col_type_is('public'::name, 'exercises'::name, 'thumbnail'::name, 'jsonb'::name);
SELECT col_type_is('public'::name, 'exercises'::name, 'archived'::name, 'boolean'::name);
SELECT col_type_is('public'::name, 'exercises'::name, 'muscles'::name, 'jsonb'::name);
SELECT col_type_is('public'::name, 'exercises'::name, 'movement'::name, 'jsonb'::name);
SELECT col_type_is('public'::name, 'exercises'::name, 'health'::name, 'jsonb'::name);
SELECT col_type_is('public'::name, 'exercises'::name, 'user_id'::name, 'text'::name);
SELECT col_type_is('public'::name, 'exercises'::name, 'created_at'::name, 'timestamp with time zone'::name);

SELECT has_pk('public'::name, 'exercises'::name, 'exercises has a primary key');
SELECT col_is_pk('public'::name, 'exercises'::name, 'id'::name, 'id is the primary key');

SELECT col_not_null('public'::name, 'exercises'::name, 'id'::name);
SELECT col_not_null('public'::name, 'exercises'::name, 'name'::name);
SELECT col_not_null('public'::name, 'exercises'::name, 'category'::name);
SELECT col_not_null('public'::name, 'exercises'::name, 'target'::name);
SELECT col_not_null('public'::name, 'exercises'::name, 'archived'::name);
SELECT col_not_null('public'::name, 'exercises'::name, 'created_at'::name);

SELECT col_default_is('public', 'exercises', 'id', 'uuidv7()', 'id default is uuidv7()');
SELECT col_default_is('public', 'exercises', 'archived', 'false', 'archived default is false');
SELECT col_default_is('public', 'exercises', 'created_at', 'now()', 'created_at default is now()');

SELECT fk_ok('public', 'exercises', 'user_id', 'public', 'profiles', 'id');

SELECT has_index('public'::name, 'exercises'::name, 'exercises_global_name_idx'::name);
SELECT has_index('public'::name, 'exercises'::name, 'exercises_user_name_idx'::name);
SELECT has_index('public'::name, 'exercises'::name, 'exercises_user_id_idx'::name);
SELECT has_index('public'::name, 'exercises'::name, 'exercises_movement_groups_idx'::name);

SELECT index_is_unique('public'::name, 'exercises'::name, 'exercises_global_name_idx'::name);
SELECT index_is_unique('public'::name, 'exercises'::name, 'exercises_user_name_idx'::name);

SELECT * FROM finish();

ROLLBACK;
