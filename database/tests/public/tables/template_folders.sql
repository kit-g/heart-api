BEGIN;

SELECT plan(28);

SELECT has_table('public'::name, 'template_folders'::name);

SELECT columns_are(
               'public',
               'template_folders',
               ARRAY [
                   'id',
                   'user_id',
                   'name',
                   'order_index',
                   'created_at'
                   ]
       );

SELECT col_type_is('public'::name, 'template_folders'::name, 'id'::name, 'uuid'::name);
SELECT col_type_is('public'::name, 'template_folders'::name, 'user_id'::name, 'text'::name);
SELECT col_type_is('public'::name, 'template_folders'::name, 'name'::name, 'text'::name);
SELECT col_type_is('public'::name, 'template_folders'::name, 'order_index'::name, 'integer'::name);
SELECT col_type_is('public'::name, 'template_folders'::name, 'created_at'::name, 'timestamp with time zone'::name);

SELECT has_pk('public'::name, 'template_folders'::name, 'template_folders has a primary key');
SELECT col_is_pk('public'::name, 'template_folders'::name, 'id'::name, 'id is the primary key');

SELECT col_not_null('public'::name, 'template_folders'::name, 'id'::name);
SELECT col_not_null('public'::name, 'template_folders'::name, 'user_id'::name);
SELECT col_not_null('public'::name, 'template_folders'::name, 'name'::name);
SELECT col_not_null('public'::name, 'template_folders'::name, 'order_index'::name);
SELECT col_not_null('public'::name, 'template_folders'::name, 'created_at'::name);

SELECT col_default_is('public', 'template_folders', 'id', 'uuidv7()', 'id default is uuidv7()');
SELECT col_default_is('public', 'template_folders', 'order_index', '0', 'order_index default is 0');
SELECT col_default_is('public', 'template_folders', 'created_at', 'now()', 'created_at default is now()');

SELECT fk_ok('public', 'template_folders', 'user_id', 'public', 'profiles', 'id');

SELECT has_index('public'::name, 'template_folders'::name, 'template_folders_user_name_idx'::name);
SELECT index_is_unique('public'::name, 'template_folders'::name, 'template_folders_user_name_idx'::name);
SELECT col_is_unique('public'::name, 'template_folders'::name, ARRAY ['id', 'user_id']);

-- fixtures for the behavioral assertions below
DO
$$
BEGIN
    PERFORM create_test_profile('folder-owner');
    PERFORM create_test_profile('folder-stranger');
    PERFORM create_test_template(_user_id := 'folder-owner', _name := 'Owned Template');
    PERFORM create_test_template(_user_id := 'folder-stranger', _name := 'Stranger Template');
END
$$;

SELECT lives_ok(
               $$
               INSERT INTO template_folders (id, user_id, name)
               VALUES ('01960000-0000-7000-8000-00000000f001', 'folder-owner', 'Push')
               $$,
               'a named folder belongs to its owner'
       );

SELECT throws_ok(
               $$
               INSERT INTO template_folders (user_id, name) VALUES ('folder-owner', '   ')
               $$,
               '23514',
               NULL,
               'a blank folder name is rejected'
       );

SELECT throws_ok(
               $$
               INSERT INTO template_folders (user_id, name) VALUES ('folder-owner', 'push')
               $$,
               '23505',
               NULL,
               'folder names are unique per user regardless of case'
       );

SELECT lives_ok(
               $$
               UPDATE templates SET folder_id = '01960000-0000-7000-8000-00000000f001'
               WHERE name = 'Owned Template'
               $$,
               'a template files into a folder owned by the same user'
       );

SELECT throws_ok(
               $$
               UPDATE templates SET folder_id = '01960000-0000-7000-8000-00000000f001'
               WHERE name = 'Stranger Template'
               $$,
               '23503',
               NULL,
               'a template cannot file into another user''s folder'
       );

SELECT lives_ok(
               $$
               DELETE FROM template_folders WHERE id = '01960000-0000-7000-8000-00000000f001'
               $$,
               'a folder can be deleted while it still holds templates'
       );

SELECT is(
               (SELECT count(*) FROM templates WHERE name = 'Owned Template' AND folder_id IS NULL),
               1::bigint,
               'deleting a folder unfiles its templates rather than destroying them'
       );

SELECT * FROM finish();

ROLLBACK;
