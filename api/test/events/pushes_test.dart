import 'package:heart/events/devices_changed.dart';
import 'package:heart/events/pushes.dart';
import 'package:heart/globals/config.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/middleware/events.dart';
import 'package:heart/notifications/notifier.dart';
import 'package:heart/notifications/topics.dart';
import 'package:mockito/mockito.dart';
import 'package:relic_core/relic_core.dart';
import 'package:test/test.dart';

import '../mocks.mocks.dart';

Request _request() => RequestInternal.create(Method.post, Uri.parse('http://localhost/events'), Object());

void main() {
  late MockPushService push;
  late MockKeyService keys;
  late MockEventPublisher publisher;
  late MockAppConfig config;
  late Request request;

  setUp(() {
    push = MockPushService();
    keys = MockKeyService();
    publisher = MockEventPublisher();
    config = MockAppConfig();

    when(config.firebaseEventsQueueUrl).thenReturn('https://sqs.test/heart-firebase-events');
    when(config.defaultLocale).thenReturn('en');
    when(
      publisher.publish(queueUrl: anyNamed('queueUrl'), message: anyNamed('message')),
    ).thenAnswer((_) async {});
    when(push.getPushPreferences(userId: anyNamed('userId'))).thenAnswer((_) async => []);

    request = _request()
      ..pushService = push
      ..keyService = keys
      ..events = publisher
      ..config = config;
  });

  void audience(
    String userId,
    List<({String token, String locale})> devices, {
    String? forTopic,
    String? actorName,
  }) {
    when(
      push.getPushAudience(
        userId: userId,
        topic: anyNamed('topic'),
        connectionId: anyNamed('connectionId'),
        actorId: anyNamed('actorId'),
      ),
    ).thenAnswer(
      (_) async => (blocked: false, forPerson: null, forTopic: forTopic, devices: devices, actorName: actorName),
    );
  }

  List<Map<String, dynamic>> sent() {
    return verify(
      publisher.publish(queueUrl: 'https://sqs.test/heart-firebase-events', message: captureAnyNamed('message')),
    ).captured.cast<Map<String, dynamic>>();
  }

  group('the daily digests', () {
    const digest = 'coaching.workout_digest';

    test('one person failing to get theirs does not cost the people after them', () async {
      when(push.claimDueDigests(localHour: anyNamed('localHour'))).thenAnswer(
        (_) async => [
          (userId: 'a', topic: digest),
          (userId: 'b', topic: digest),
          (userId: 'c', topic: digest),
        ],
      );
      audience('a', [(token: 't-a', locale: 'en')]);
      when(
        push.getPushAudience(
          userId: 'b',
          topic: anyNamed('topic'),
          connectionId: anyNamed('connectionId'),
          actorId: anyNamed('actorId'),
        ),
      ).thenThrow(Exception('pool timeout'));
      audience('c', [(token: 't-c', locale: 'en')]);

      await deliverDigests(request);

      expect([for (final message in sent()) ...message['tokens'] as List], ['t-a', 't-c']);
    });

    test('a digest one person still wants goes out though the topic is off', () async {
      when(push.getPushPreferences(userId: 'coach')).thenAnswer(
        (_) async => [
          (topic: digest, connectionId: null, delivery: 'off'),
          (topic: digest, connectionId: 'c-1', delivery: 'daily'),
        ],
      );
      audience('coach', [(token: 't', locale: 'en')], forTopic: 'off');

      await request.deliverDigest(userId: 'coach', topic: .coachingWorkoutDigest);

      expect(sent().single['title'], 'Your clients trained today');
    });

    test('nothing goes once the topic is off and nobody is wanted', () async {
      when(push.getPushPreferences(userId: 'coach')).thenAnswer(
        (_) async => [
          (topic: digest, connectionId: null, delivery: 'off'),
          (topic: 'coaching.message', connectionId: 'c-1', delivery: 'instant'),
        ],
      );
      audience('coach', [(token: 't', locale: 'en')], forTopic: 'off');

      await request.deliverDigest(userId: 'coach', topic: .coachingWorkoutDigest);

      verifyNever(publisher.publish(queueUrl: anyNamed('queueUrl'), message: anyNamed('message')));
    });

    test('a digest says the same thing every time, so a newer one replaces one still waiting', () async {
      audience('coach', [(token: 't', locale: 'en')]);
      await request.deliverDigest(userId: 'coach', topic: .coachingWorkoutDigest);
      expect(sent().single['collapseKey'], digest);
    });
  });

  group('a requested push', () {
    test('someone with no name is still someone, in the push\'s language', () async {
      audience('coach', [(token: 't-en', locale: 'en'), (token: 't-ru', locale: 'ru')]);

      await pushRequested(request, {
        'type': 'push.requested',
        'userId': 'coach',
        'topic': PushTopic.invitationAccepted.key,
        'actorId': 'student',
      });

      expect(
        {for (final message in sent()) message['title']},
        {
          'Someone accepted your invitation',
          'Кто-то: приглашение принято',
        },
      );
    });

    test('two messages are two things to hear about, so neither replaces the other', () async {
      audience('coach', [(token: 't', locale: 'en')]);

      await pushRequested(request, {
        'type': 'push.requested',
        'userId': 'coach',
        'topic': PushTopic.coachingMessage.key,
        'name': 'Alex',
        'actorId': 'student',
      });

      final message = sent().single;
      expect(message['title'], 'Alex messaged you');
      expect(message.containsKey('collapseKey'), isFalse);
    });

    test('the name is the one their profile holds, and the sign-in\'s only without one', () async {
      audience('coach', [(token: 't', locale: 'en')], actorName: 'Alex Rivera');

      await pushRequested(request, {
        'type': 'push.requested',
        'userId': 'coach',
        'topic': PushTopic.coachingMessage.key,
        'name': 'alex@relay.example',
        'actorId': 'student',
      });

      expect(sent().single['title'], 'Alex Rivera messaged you');
    });

    test('a silent push has no words, so devices in two languages get one message', () async {
      audience('coach', [(token: 't-en', locale: 'en'), (token: 't-ru', locale: 'ru')]);

      await pushRequested(request, {
        'type': 'push.requested',
        'userId': 'coach',
        'topic': PushTopic.programChanged.key,
        'actorId': 'student',
      });

      final message = sent().single;
      expect(message['silent'], isTrue);
      expect(message['tokens'], ['t-en', 't-ru']);
    });
  });

  test('a change to someone\'s devices wakes each person who shares keys with them, about them', () async {
    when(keys.getKeyPeers(userId: 'student')).thenAnswer((_) async => ['coach', 'friend']);
    audience('coach', [(token: 't-coach', locale: 'en')]);
    audience('friend', [(token: 't-friend', locale: 'en')]);

    await devicesChanged(request, {'type': 'devices.changed', 'userId': 'student'});

    final messages = sent();
    expect([for (final message in messages) ...message['tokens'] as List], ['t-coach', 't-friend']);
    for (final message in messages) {
      expect(message['silent'], isTrue);
      expect(message['data'], {'topic': 'security.devices_changed', 'userId': 'student'});
      expect(message.containsKey('collapseKey'), isFalse, reason: 'one person\'s change mustn\'t hide another\'s');
    }
    verify(
      push.getPushAudience(
        userId: 'coach',
        topic: 'security.devices_changed',
        connectionId: anyNamed('connectionId'),
        actorId: 'student',
      ),
    );
  });
}
