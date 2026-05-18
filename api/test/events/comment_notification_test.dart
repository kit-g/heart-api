import 'package:heart/events/comment_notification.dart';
import 'package:heart/globals/config.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/middleware/events.dart';
import 'package:mockito/mockito.dart';
import 'package:relic_core/relic_core.dart';
import 'package:test/test.dart';

import '../mocks.mocks.dart';

Request _request() => RequestInternal.create(Method.post, Uri.parse('http://localhost/events'), Object());

void main() {
  late MockDeviceService devices;
  late MockEventPublisher publisher;
  late MockAppConfig config;
  late Request request;

  setUp(() {
    devices = MockDeviceService();
    publisher = MockEventPublisher();
    config = MockAppConfig();

    when(config.firebaseEventsQueueUrl).thenReturn('https://sqs.test/heart-firebase-events');
    when(config.defaultLocale).thenReturn('en');
    when(
      publisher.publish(queueUrl: anyNamed('queueUrl'), message: anyNamed('message')),
    ).thenAnswer((_) async {});

    request = _request()
      ..deviceService = devices
      ..events = publisher
      ..config = config;
  });

  Map<String, dynamic> event({String body = 'looks great'}) => {
    'type': 'comment.created',
    'commentId': 'c-1',
    'authorId': 'sarah-id',
    'authorName': 'Sarah',
    'ownerId': 'owner-id',
    'targetType': 'workout',
    'targetId': 'w-1',
    'body': body,
  };

  test('no devices: skips the firebase enqueue', () async {
    when(devices.tokensWithLocale('owner-id')).thenAnswer((_) async => []);

    await commentNotification(request, event());

    verifyNever(publisher.publish(queueUrl: anyNamed('queueUrl'), message: anyNamed('message')));
  });

  test('single-locale recipient: one push.notification event with localized title', () async {
    when(devices.tokensWithLocale('owner-id')).thenAnswer(
      (_) async => [(token: 't-en-1', locale: 'en'), (token: 't-en-2', locale: 'en')],
    );

    await commentNotification(request, event());

    final captured = verify(
      publisher.publish(
        queueUrl: 'https://sqs.test/heart-firebase-events',
        message: captureAnyNamed('message'),
      ),
    ).captured.single as Map<String, dynamic>;
    expect(captured['type'], 'push.notification');
    expect(captured['tokens'], ['t-en-1', 't-en-2']);
    expect(captured['title'], 'Sarah: new comment on your workout');
    expect(captured['body'], 'looks great');
    expect(captured['data'], {
      'commentId': 'c-1',
      'targetType': 'workout',
      'targetId': 'w-1',
    });
  });

  test('multi-locale recipient: one event per locale, each with its own title', () async {
    when(devices.tokensWithLocale('owner-id')).thenAnswer(
      (_) async => [
        (token: 't-en', locale: 'en'),
        (token: 't-ru-1', locale: 'ru'),
        (token: 't-ru-2', locale: 'ru'),
      ],
    );

    await commentNotification(request, event());

    final captured = verify(
      publisher.publish(
        queueUrl: 'https://sqs.test/heart-firebase-events',
        message: captureAnyNamed('message'),
      ),
    ).captured;
    expect(captured, hasLength(2));

    final byTitle = {
      for (final m in captured.cast<Map<String, dynamic>>())
        m['title'] as String: m['tokens'],
    };
    expect(byTitle['Sarah: new comment on your workout'], ['t-en']);
    expect(byTitle['Sarah: новый комментарий к вашей тренировке'], ['t-ru-1', 't-ru-2']);
  });
}
