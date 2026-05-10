BEGIN;

SELECT plan(22);

SELECT has_table('public'::name, 'template_shares'::name);

SELECT columns_are(
               'public',
               'template_shares',
               ARRAY [
                   'id',
                   'coach_id',
                   'student_id',
                   'master_template_id',
                   'student_template_id',
                   'created_at'
                   ]
       );

SELECT col_type_is('public'::name, 'template_shares'::name, 'id'::name, 'uuid'::name);
SELECT col_type_is('public'::name, 'template_shares'::name, 'coach_id'::name, 'text'::name);
SELECT col_type_is('public'::name, 'template_shares'::name, 'student_id'::name, 'text'::name);
SELECT col_type_is('public'::name, 'template_shares'::name, 'master_template_id'::name, 'uuid'::name);
SELECT col_type_is('public'::name, 'template_shares'::name, 'student_template_id'::name, 'uuid'::name);
SELECT col_type_is('public'::name, 'template_shares'::name, 'created_at'::name, 'timestamp with time zone'::name);

SELECT has_pk('public'::name, 'template_shares'::name, 'template_shares has a primary key');
SELECT col_is_pk('public'::name, 'template_shares'::name, 'id'::name, 'id is the primary key');

SELECT col_not_null('public'::name, 'template_shares'::name, 'id'::name);
SELECT col_not_null('public'::name, 'template_shares'::name, 'coach_id'::name);
SELECT col_not_null('public'::name, 'template_shares'::name, 'student_id'::name);
SELECT col_not_null('public'::name, 'template_shares'::name, 'master_template_id'::name);
SELECT col_not_null('public'::name, 'template_shares'::name, 'student_template_id'::name);

SELECT col_default_is('public', 'template_shares', 'id', 'uuidv7()', 'id default is uuidv7()');
SELECT col_default_is('public', 'template_shares', 'created_at', 'now()', 'created_at default is now()');

SELECT fk_ok('public', 'template_shares', 'coach_id', 'public', 'profiles', 'id');
SELECT fk_ok('public', 'template_shares', 'student_id', 'public', 'profiles', 'id');
SELECT fk_ok('public', 'template_shares', 'master_template_id', 'public', 'templates', 'id');
SELECT fk_ok('public', 'template_shares', 'student_template_id', 'public', 'templates', 'id');

SELECT col_is_unique('public'::name, 'template_shares'::name, ARRAY ['coach_id', 'master_template_id', 'student_id']);

SELECT * FROM finish();

ROLLBACK;
