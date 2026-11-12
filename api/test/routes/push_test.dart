import 'dart:convert';

import 'package:heart/notifications/topics.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../helpers/app_harness.dart';

void main() {
  late AppHarness app;

  setUp(() async => app = await AppHarness.start());
  tearDown(() => app.stop());

  group('GET /push/settings', () {
    test('every topic a person can choose, with what they said, and no silent one', () async {
      when(app.config.supportedLocales).thenReturn(['en']);
      when(app.config.defaultLocale).thenReturn('en');
      when(app.db.getPushPreferences(userId: anyNamed('userId'))).thenAnswer(
        (_) async => [
          (topic: 'coaching.message', connectionId: null, delivery: 'off'),
          (topic: 'coaching.workout_digest', connectionId: 'c', delivery: 'off'),
        ],
      );

      final res = await app.send('GET', '/push/settings');
      expect(res.status, 200);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final topics = {
        for (final topic in (body['topics'] as List).cast<Map<String, dynamic>>()) topic['topic'] as String: topic,
      };
      expect(topics.keys, unorderedEquals(PushTopic.settable.map((topic) => topic.key)));
      expect(topics['coaching.message']?['delivery'], 'off');
      expect(topics['coaching.message']?['name'], 'Messages');
      expect(topics['coaching.workout_digest']?['delivery'], 'daily');
      expect(topics['coaching.workout_digest']?['options'], ['daily', 'off']);
      expect(topics['coaching.message']?['perPersonAs'], ['coach', 'student', 'peer']);
      expect(topics['coaching.workout_digest']?['perPersonAs'], isEmpty, reason: 'one person off stops nothing');
      expect(topics['coaching.program_received']?['perPersonAs'], ['student']);
      expect(topics['coaching.invitation_accepted']?['perPersonAs'], isEmpty);
      expect(topics['comment.created']?['perPersonAs'], ['coach', 'student', 'peer']);
      expect(topics['reaction.created']?['perPersonAs'], ['coach', 'student', 'peer']);
      expect(body['forPeople'], [
        {'topic': 'coaching.workout_digest', 'connectionId': 'c', 'delivery': 'off'},
      ]);
    });
  });

  group('PUT /push/settings/:topic', () {
    void stub() {
      when(
        app.db.setPushPreference(
          userId: anyNamed('userId'),
          topic: anyNamed('topic'),
          delivery: anyNamed('delivery'),
          connectionId: anyNamed('connectionId'),
        ),
      ).thenAnswer((_) async {});
    }

    test('takes what the topic offers', () async {
      stub();
      final res = await app.send('PUT', '/push/settings/coaching.message', body: {'delivery': 'off'});
      expect(res.status, 204);
    });

    test('refuses what it does not', () async {
      final res = await app.send('PUT', '/push/settings/coaching.message', body: {'delivery': 'daily'});
      expect(res.status, 400);
      expect(res.body, contains('invalid_delivery'));
    });

    test('a topic that does not exist, or says nothing, is not there', () async {
      for (final topic in ['nonsense', 'coaching.program_changed']) {
        final res = await app.send('PUT', '/push/settings/$topic', body: {'delivery': 'off'});
        expect(res.status, 404, reason: topic);
      }
    });
  });

  group('DELETE /push/settings/:topic', () {
    test('goes back to what the topic does, for one relationship or the whole topic', () async {
      when(
        app.db.clearPushPreference(
          userId: anyNamed('userId'),
          topic: anyNamed('topic'),
          connectionId: anyNamed('connectionId'),
        ),
      ).thenAnswer((_) async {});
      const connection = '01900000-0000-7000-8000-000000000001';

      expect((await app.send('DELETE', '/push/settings/coaching.message?connectionId=$connection')).status, 204);
      expect((await app.send('DELETE', '/push/settings/coaching.message')).status, 204);
      verify(
        app.db.clearPushPreference(userId: anyNamed('userId'), topic: 'coaching.message', connectionId: connection),
      );
      verify(app.db.clearPushPreference(userId: anyNamed('userId'), topic: 'coaching.message', connectionId: null));
    });

    test('a topic that does not exist, or says nothing, is not there, as for PUT', () async {
      for (final topic in ['nonsense', 'coaching.program_changed']) {
        final res = await app.send('DELETE', '/push/settings/$topic');
        expect(res.status, 404, reason: topic);
      }
      verifyNever(
        app.db.clearPushPreference(
          userId: anyNamed('userId'),
          topic: anyNamed('topic'),
          connectionId: anyNamed('connectionId'),
        ),
      );
    });

    test('a connectionId has to be one', () async {
      final res = await app.send('DELETE', '/push/settings/coaching.message?connectionId=nope');
      expect(res.status, 400);
    });
  });
}
