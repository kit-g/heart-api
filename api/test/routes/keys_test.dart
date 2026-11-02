import 'package:heart_models/heart_models.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../helpers/app_harness.dart';

void main() {
  late AppHarness app;

  setUp(() async => app = await AppHarness.start());
  tearDown(() => app.stop());

  const device = '01900000-0000-7000-8000-000000000001';
  const other = '01900000-0000-7000-8000-000000000002';
  const item = '01900000-0000-7000-8000-000000000003';

  Map<String, dynamic> body(Object? content) => {
    'id': item,
    'recipientDeviceId': device,
    'senderDeviceId': other,
    'kind': 'key',
    'content': content,
  };

  group('POST /keys/queue', () {
    void stub() {
      when(
        app.db.enqueue(
          userId: anyNamed('userId'),
          id: anyNamed('id'),
          recipientDeviceId: anyNamed('recipientDeviceId'),
          senderDeviceId: anyNamed('senderDeviceId'),
          kind: anyNamed('kind'),
          content: anyNamed('content'),
        ),
      ).thenAnswer((_) async => true);
    }

    test('takes a string', () async {
      stub();
      final res = await app.send('POST', '/keys/queue', body: body('sealed'));
      expect(res.status, 204);
    });

    test('an object is refused, so nothing readable rides in structure', () async {
      final res = await app.send('POST', '/keys/queue', body: body({'text': 'hello'}));
      expect(res.status, 400);
    });

    test('over 1 KB is refused', () async {
      final res = await app.send('POST', '/keys/queue', body: body('x' * 1025));
      expect(res.status, 400);
    });
  });

  test('publishing and removing a device tell the people who share keys, through the real app', () async {
    when(
      app.db.publishDevice(
        userId: anyNamed('userId'),
        id: anyNamed('id'),
        identityKey: anyNamed('identityKey'),
        signingKey: anyNamed('signingKey'),
        fallbackKey: anyNamed('fallbackKey'),
        signature: anyNamed('signature'),
        vouchedBy: anyNamed('vouchedBy'),
      ),
    ).thenAnswer(
      (_) async => CryptoDevice(
        id: device,
        userId: 'u',
        identityKey: 'i',
        signingKey: 's',
        fallbackKey: 'f',
        createdAt: DateTime.utc(2026),
      ),
    );
    when(app.db.removeDevice(userId: anyNamed('userId'), deviceId: anyNamed('deviceId'))).thenAnswer((_) async {});
    when(app.config.eventsQueueUrl).thenReturn('https://sqs.test/events');
    when(app.events.publish(queueUrl: anyNamed('queueUrl'), message: anyNamed('message'))).thenAnswer((_) async {});

    final published = await app.send(
      'POST',
      '/keys/devices',
      body: {'id': device, 'identityKey': 'i', 'signingKey': 's', 'fallbackKey': 'f'},
    );
    expect(published.status, 201);

    final removed = await app.send('DELETE', '/keys/devices/$device');
    expect(removed.status, 204);

    verify(app.events.publish(queueUrl: anyNamed('queueUrl'), message: anyNamed('message'))).called(2);
  });

  test('one-time keys must map a name to a key', () async {
    final res = await app.send('POST', '/keys/devices/$device/one-time-keys', body: {'keys': []});
    expect(res.status, 400);
  });

  test('confirmations must be item ids', () async {
    final res = await app.send(
      'POST',
      '/keys/queue/confirmations',
      body: {
        'deviceId': device,
        'ids': ['nope'],
      },
    );
    expect(res.status, 400);
  });

  test('the routes need a sign-in', () async {
    final res = await app.send('GET', '/keys/devices', token: null);
    expect(res.status, 401);
  });
}
