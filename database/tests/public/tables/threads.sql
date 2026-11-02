BEGIN;

SELECT plan(28);

SELECT has_table('public'::name, 'threads'::name);

SELECT columns_are(
               'public',
               'threads',
               ARRAY [
                   'id',
                   'connection_id',
                   'person_a',
                   'person_b',
                   'cleared_at',
                   'cleared_by',
                   'created_at'
                   ]
       );

SELECT col_is_pk('public'::name, 'threads'::name, 'id'::name);

SELECT col_is_unique('public', 'threads', ARRAY ['connection_id'], 'one thread per connection');

SELECT fk_ok('public', 'threads', 'connection_id', 'public', 'connections', 'id');
SELECT fk_ok('public', 'threads', 'person_a', 'public', 'profiles', 'id');
SELECT fk_ok('public', 'threads', 'person_b', 'public', 'profiles', 'id');

SELECT has_table('public'::name, 'thread_items'::name);

SELECT columns_are(
               'public',
               'thread_items',
               ARRAY [
                   'id',
                   'thread_id',
                   'sender_id',
                   'kind',
                   'subject_type',
                   'subject_id',
                   'content',
                   'commitment',
                   'tag',
                   'tag_key',
                   'at',
                   'xid',
                   'created_at'
                   ]
       );

SELECT col_is_pk('public'::name, 'thread_items'::name, 'id'::name);

SELECT col_type_is('public'::name, 'thread_items'::name, 'xid'::name, 'xid8'::name);

SELECT col_default_is('public', 'thread_items', 'xid', 'pg_current_xact_id()', 'ordered by the storing transaction');

SELECT fk_ok('public', 'thread_items', 'thread_id', 'public', 'threads', 'id');
SELECT fk_ok('public', 'thread_items', 'sender_id', 'public', 'profiles', 'id');

SELECT has_index('public'::name, 'thread_items'::name, 'thread_items_order_idx'::name);
SELECT has_index('public'::name, 'thread_items'::name, 'thread_items_subject_idx'::name);

SELECT has_table('public'::name, 'thread_reads'::name);

SELECT col_is_pk('public'::name, 'thread_reads'::name, ARRAY ['thread_id', 'user_id'], 'one position per person');

SELECT has_table('public'::name, 'coach_notes'::name);

SELECT columns_are(
               'public',
               'coach_notes',
               ARRAY [
                   'id',
                   'coach_id',
                   'connection_id',
                   'content',
                   'created_at',
                   'updated_at'
                   ]
       );

SELECT fk_ok('public', 'coach_notes', 'coach_id', 'public', 'profiles', 'id');
SELECT fk_ok('public', 'coach_notes', 'connection_id', 'public', 'connections', 'id');

SELECT has_table('public'::name, 'reports'::name);

SELECT columns_are(
               'public',
               'reports',
               ARRAY [
                   'id',
                   'reporter_id',
                   'reported_id',
                   'connection_id',
                   'reason',
                   'sealed',
                   'verified',
                   'created_at',
                   'closed_at'
                   ]
       );

SELECT hasnt_fk('public'::name, 'reports'::name, 'a report outlives both people');

DO
$$
BEGIN
    PERFORM create_test_profile('thread-a');
    PERFORM create_test_profile('thread-b');
    INSERT INTO threads (id, person_a, person_b) VALUES ('01900000-0000-7000-8000-00000000aaaa', 'thread-a', 'thread-b');
END
$$;

SELECT throws_ok(
               $$
               INSERT INTO thread_items (id, thread_id, content, commitment, tag, tag_key, at, created_at, subject_type)
               VALUES (uuidv7(), '01900000-0000-7000-8000-00000000aaaa', 'x', 'c', 't', 'k', now(), now(), 'exercise_set')
               $$,
               '23514',
               NULL,
               'a subject has a type and an id together'
       );

DELETE FROM profiles WHERE id = 'thread-a';

SELECT is(
               (SELECT person_a FROM threads WHERE id = '01900000-0000-7000-8000-00000000aaaa'),
               NULL,
               'one account going leaves the thread for the other'
       );

DELETE FROM profiles WHERE id = 'thread-b';

SELECT is_empty(
               $$ SELECT 1 FROM threads WHERE id = '01900000-0000-7000-8000-00000000aaaa' $$,
               'it goes when nobody is left'
       );

SELECT * FROM finish();

ROLLBACK;
