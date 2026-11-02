BEGIN;

SELECT plan(17);

SELECT has_table('public'::name, 'push_preferences'::name);

SELECT columns_are(
               'public',
               'push_preferences',
               ARRAY [
                   'id',
                   'user_id',
                   'topic',
                   'connection_id',
                   'delivery',
                   'updated_at'
                   ]
       );

SELECT col_is_pk('public'::name, 'push_preferences'::name, 'id'::name);

SELECT col_not_null('public'::name, 'push_preferences'::name, 'user_id'::name);
SELECT col_not_null('public'::name, 'push_preferences'::name, 'topic'::name);
SELECT col_not_null('public'::name, 'push_preferences'::name, 'delivery'::name);

SELECT fk_ok('public', 'push_preferences', 'user_id', 'public', 'profiles', 'id');
SELECT fk_ok('public', 'push_preferences', 'connection_id', 'public', 'connections', 'id');

SELECT has_index('public'::name, 'push_preferences'::name, 'push_preferences_topic_key'::name);
SELECT has_index('public'::name, 'push_preferences'::name, 'push_preferences_person_key'::name);
SELECT has_index('public'::name, 'push_preferences'::name, 'push_preferences_connection_idx'::name);

DO
$$
BEGIN
    PERFORM create_test_profile('push-a');
END
$$;

SELECT lives_ok(
               $$
               INSERT INTO push_preferences (user_id, topic, delivery) VALUES ('push-a', 'coaching.message', 'off')
               $$,
               'an answer for a topic'
       );

SELECT throws_ok(
               $$
               INSERT INTO push_preferences (user_id, topic, delivery) VALUES ('push-a', 'coaching.message', 'daily')
               $$,
               '23505',
               NULL,
               'one per person and topic'
       );

SELECT throws_ok(
               $$
               INSERT INTO push_preferences (user_id, topic, delivery) VALUES ('push-a', 'Not A Topic', 'off')
               $$,
               '23514',
               NULL,
               'a topic is a key'
       );

SELECT throws_ok(
               $$
               INSERT INTO push_preferences (user_id, topic, delivery) VALUES ('push-a', 'a.topic', 'Not A Word')
               $$,
               '23514',
               NULL,
               'a delivery is a word'
       );

SELECT has_table('public'::name, 'push_digests'::name);

SELECT col_is_pk('public'::name, 'push_digests'::name, ARRAY ['user_id', 'topic'], 'one owed per person and topic');

SELECT * FROM finish();

ROLLBACK;
