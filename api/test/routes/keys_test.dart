import 'dart:convert';

import 'package:heart/inputs/inputs.dart';
import 'package:heart/models/errors.dart';
import 'package:heart_models/heart_models.dart';
import 'package:mockito/mockito.dart';
import 'package:relic_core/relic_core.dart' show MimeType;
import 'package:test/test.dart';

import '../helpers/app_harness.dart';
import '../helpers/request.dart';

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
    void stub({String? notify}) {
      when(
        app.db.enqueue(
          userId: anyNamed('userId'),
          id: anyNamed('id'),
          recipientDeviceId: anyNamed('recipientDeviceId'),
          senderDeviceId: anyNamed('senderDeviceId'),
          kind: anyNamed('kind'),
          content: anyNamed('content'),
        ),
      ).thenAnswer((_) async => (delivered: true, notify: notify));
      when(app.config.eventsQueueUrl).thenReturn('https://sqs.test/events');
    }

    test('an arrival wakes the recipient with a silent push naming only the device', () async {
      stub(notify: 'them');
      when(app.events.publish(queueUrl: anyNamed('queueUrl'), message: anyNamed('message'))).thenAnswer((_) async {});

      final res = await app.send('POST', '/keys/queue', body: body('sealed'));

      expect(res.status, 204);
      final message =
          verify(app.events.publish(queueUrl: anyNamed('queueUrl'), message: captureAnyNamed('message')))
                  .captured
                  .single
              as Map;
      expect(message, {
        'type': 'push.requested',
        'userId': 'them',
        'topic': 'security.queue_waiting',
        'actorId': 'u1',
        'data': {'deviceId': device},
      });
    });

    test('nothing to wake for sends no push', () async {
      stub();
      final res = await app.send('POST', '/keys/queue', body: body('sealed'));
      expect(res.status, 204);
      verifyNever(app.events.publish(queueUrl: anyNamed('queueUrl'), message: anyNamed('message')));
    });

    test('a push that cannot go out leaves the delivered item delivered', () async {
      stub(notify: 'them');
      when(
        app.events.publish(queueUrl: anyNamed('queueUrl'), message: anyNamed('message')),
      ).thenThrow(Exception('sqs down'));

      final res = await app.send('POST', '/keys/queue', body: body('sealed'));
      expect(res.status, 204);
    });

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

  void stubPublish({required bool added}) {
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
      (_) async => (
        device: CryptoDevice(
          id: device,
          userId: 'u',
          identityKey: 'i',
          signingKey: 's',
          fallbackKey: 'f',
          createdAt: DateTime.utc(2026),
        ),
        added: added,
      ),
    );
  }

  test('publishing and removing a device tell the people who share keys, through the real app', () async {
    stubPublish(added: true);
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

  test('a device publishing itself again tells nobody', () async {
    stubPublish(added: false);

    final published = await app.send(
      'POST',
      '/keys/devices',
      body: {'id': device, 'identityKey': 'i', 'signingKey': 's', 'fallbackKey': 'f'},
    );
    expect(published.status, 201);
    verifyNever(app.events.publish(queueUrl: anyNamed('queueUrl'), message: anyNamed('message')));
  });

  test('removing a device nobody had tells nobody', () async {
    when(
      app.db.removeDevice(userId: anyNamed('userId'), deviceId: anyNamed('deviceId')),
    ).thenThrow(const NotFound(type: 'Device', id: device));

    final res = await app.send('DELETE', '/keys/devices/$device');
    expect(res.status, 404);
    verifyNever(app.events.publish(queueUrl: anyNamed('queueUrl'), message: anyNamed('message')));
  });

  test('a device in the path that cannot be one is not there, and a query one is refused', () async {
    for (final (method, path, body) in [
      ('DELETE', '/keys/devices/nope', null),
      ('PUT', '/keys/devices/nope/fallback', {'key': 'k'}),
      ('PUT', '/keys/devices/nope/vouch', {'vouchedBy': other, 'signature': 'sig'}),
      ('GET', '/keys/devices/nope/one-time-keys', null),
      (
        'POST',
        '/keys/devices/nope/one-time-keys',
        {
          'keys': [
            {'id': 'k', 'key': 'v'},
          ],
        },
      ),
    ]) {
      final res = await app.send(method, path, body: body);
      expect(res.status, 404, reason: '$method $path');
    }
    expect((await app.send('GET', '/keys/queue?deviceId=nope')).status, 400);
    expect((await app.send('GET', '/keys/queue')).status, 400);
    verifyZeroInteractions(app.db);
  });

  test('a vouch is a signature and the device that made it, or nothing', () async {
    for (final vouch in [
      {'vouchedBy': other},
      {'signature': 'sig'},
      {'vouchedBy': other, 'signature': ''},
    ]) {
      final res = await app.send(
        'POST',
        '/keys/devices',
        body: {'id': device, 'identityKey': 'i', 'signingKey': 's', 'fallbackKey': 'f', ...vouch},
      );
      expect(res.status, 400, reason: '$vouch');
    }
  });

  test('one-time keys are a list of {id, key}, each id once, no more than a device holds', () async {
    for (final keys in [
      [],
      {'k': 'v'},
      [
        {'id': 'k', 'key': 1},
      ],
      [
        {'id': '', 'key': 'v'},
      ],
      [
        {'id': 'k', 'key': 'v'},
        {'id': 'k', 'key': 'w'},
      ],
      [
        for (var i = 0; i < 51; i++) {'id': 'k$i', 'key': 'v'},
      ],
    ]) {
      final res = await app.send('POST', '/keys/devices/$device/one-time-keys', body: {'keys': keys});
      expect(res.status, 400, reason: '$keys');
    }
    verifyZeroInteractions(app.db);
  });

  test('a key id that reads like a health field is only a value, so it gets through', () async {
    when(
      app.db.addOneTimeKeys(userId: anyNamed('userId'), deviceId: anyNamed('deviceId'), keys: anyNamed('keys')),
    ).thenAnswer((_) async => 1);

    final res = await app.send(
      'POST',
      '/keys/devices/$device/one-time-keys',
      body: {
        'keys': [
          {'id': 'aHRvSleep', 'key': 'v'},
        ],
      },
    );
    expect(res.status, 200);
  });

  group('PUT /keys/devices/:deviceId/vouch', () {
    void stub({required bool changed}) {
      when(
        app.db.vouchForDevice(
          userId: anyNamed('userId'),
          deviceId: anyNamed('deviceId'),
          vouchedBy: anyNamed('vouchedBy'),
          signature: anyNamed('signature'),
        ),
      ).thenAnswer(
        (_) async => (
          device: CryptoDevice(
            id: device,
            userId: 'u1',
            identityKey: 'i',
            signingKey: 's',
            fallbackKey: 'f',
            signature: 'sig',
            vouchedBy: other,
            createdAt: DateTime.utc(2026),
          ),
          changed: changed,
        ),
      );
      when(app.config.eventsQueueUrl).thenReturn('https://sqs.test/events');
      when(app.events.publish(queueUrl: anyNamed('queueUrl'), message: anyNamed('message'))).thenAnswer((_) async {});
    }

    test('vouches for the caller\'s device and tells the people who share keys', () async {
      stub(changed: true);
      final res = await app.send('PUT', '/keys/devices/$device/vouch', body: {'vouchedBy': other, 'signature': 'sig'});

      expect(res.status, 200);
      expect(CryptoDevice.fromJson(jsonDecode(res.body) as Map).id, device);
      verify(app.db.vouchForDevice(userId: 'u1', deviceId: device, vouchedBy: other, signature: 'sig')).called(1);
      verify(app.events.publish(queueUrl: anyNamed('queueUrl'), message: anyNamed('message'))).called(1);
    });

    test('the same vouch again tells nobody', () async {
      stub(changed: false);
      final res = await app.send('PUT', '/keys/devices/$device/vouch', body: {'vouchedBy': other, 'signature': 'sig'});

      expect(res.status, 200);
      verifyNever(app.events.publish(queueUrl: anyNamed('queueUrl'), message: anyNamed('message')));
    });

    test('a vouch is both a device and a signature', () async {
      for (final vouch in [
        {'vouchedBy': other},
        {'signature': 'sig'},
        {'vouchedBy': 'nope', 'signature': 'sig'},
        {'vouchedBy': other, 'signature': ''},
        {'vouchedBy': other, 'signature': 'x' * 257},
      ]) {
        final res = await app.send('PUT', '/keys/devices/$device/vouch', body: vouch);
        expect(res.status, 400, reason: '$vouch');
      }
      verifyZeroInteractions(app.db);
    });
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

  CryptoDevice published({String userId = 'them'}) => CryptoDevice(
    id: device,
    userId: userId,
    identityKey: 'i',
    signingKey: 's',
    fallbackKey: 'f',
    createdAt: DateTime.utc(2026),
  );

  group('reading devices', () {
    setUp(() {
      when(
        app.db.getDevices(readerId: anyNamed('readerId'), ownerId: anyNamed('ownerId')),
      ).thenAnswer((_) async => [published()]);
    });

    test('someone else\'s, as the caller reads them', () async {
      final res = await app.send('GET', '/keys/devices?userId=them');

      expect(res.status, 200);
      expect(CryptoDevices.fromJson(jsonDecode(res.body) as Map).devices.single.id, device);
      verify(app.db.getDevices(readerId: 'u1', ownerId: 'them')).called(1);
    });

    test('the caller\'s own when nobody else is named', () async {
      final res = await app.send('GET', '/keys/devices');

      expect(res.status, 200);
      verify(app.db.getDevices(readerId: 'u1', ownerId: 'u1')).called(1);
    });
  });

  test('a new fallback key goes on the caller\'s device, 204', () async {
    when(
      app.db.replaceFallbackKey(userId: anyNamed('userId'), deviceId: anyNamed('deviceId'), key: anyNamed('key')),
    ).thenAnswer((_) async {});

    final res = await app.send('PUT', '/keys/devices/$device/fallback', body: {'key': 'k2'});

    expect(res.status, 204);
    verify(app.db.replaceFallbackKey(userId: 'u1', deviceId: device, key: 'k2')).called(1);
  });

  test('adding one-time keys answers how many the device holds now, and counting them does too', () async {
    when(
      app.db.addOneTimeKeys(userId: anyNamed('userId'), deviceId: anyNamed('deviceId'), keys: anyNamed('keys')),
    ).thenAnswer((_) async => 7);
    when(
      app.db.countOneTimeKeys(userId: anyNamed('userId'), deviceId: anyNamed('deviceId')),
    ).thenAnswer((_) async => 7);

    final added = await app.send(
      'POST',
      '/keys/devices/$device/one-time-keys',
      body: {
        'keys': [
          {'id': 'k1', 'key': 'v1'},
        ],
      },
    );
    expect(added.status, 200);
    expect(OneTimeKeyCount.fromJson(jsonDecode(added.body) as Map).count, 7);
    verify(app.db.addOneTimeKeys(userId: 'u1', deviceId: device, keys: {'k1': 'v1'})).called(1);

    final counted = await app.send('GET', '/keys/devices/$device/one-time-keys');
    expect(counted.status, 200);
    expect(OneTimeKeyCount.fromJson(jsonDecode(counted.body) as Map).count, 7);
    verify(app.db.countOneTimeKeys(userId: 'u1', deviceId: device)).called(1);
  });

  group('POST /keys/claims/:ownerId', () {
    setUp(() {
      when(
        app.db.claimKeys(
          claimerId: anyNamed('claimerId'),
          ownerId: anyNamed('ownerId'),
          deviceIds: anyNamed('deviceIds'),
        ),
      ).thenAnswer((_) async => [published()]);
    });

    test('takes one from each of the owner\'s devices, as the caller', () async {
      final res = await app.send('POST', '/keys/claims/them', body: {});

      expect(res.status, 200);
      expect(CryptoDevices.fromJson(jsonDecode(res.body) as Map).devices, hasLength(1));
      verify(app.db.claimKeys(claimerId: 'u1', ownerId: 'them')).called(1);
    });

    test('with no body at all, too, whatever its content type says', () async {
      for (final headers in [
        const <String, String>{},
        {'content-type': 'application/json'},
      ]) {
        final res = await app.send('POST', '/keys/claims/them', extraHeaders: headers);
        expect(res.status, 200, reason: '$headers');
      }
      verify(app.db.claimKeys(claimerId: 'u1', ownerId: 'them')).called(2);
    });

    test('a body that is not JSON is refused, not read as asking for every device', () async {
      final req = textRequest(body: '{"deviceIds": ["$device"]}', mimeType: MimeType.plainText);
      await expectLater(ClaimKeysIn.fromRequest(req), throwsA(isA<UnsupportedMediaType>()));
    });

    test('only from the devices named, each once, whatever their case', () async {
      final res = await app.send(
        'POST',
        '/keys/claims/them',
        body: {
          'deviceIds': [device, device.toUpperCase()],
        },
      );
      expect(res.status, 200);
      verify(app.db.claimKeys(claimerId: 'u1', ownerId: 'them', deviceIds: [device])).called(1);
    });

    test('names one to ten devices', () async {
      for (final ids in [
        [],
        ['nope'],
        [for (var i = 0; i < 11; i++) '01900000-0000-7000-8000-0000000001${i.toString().padLeft(2, '0')}'],
        device,
      ]) {
        final res = await app.send('POST', '/keys/claims/them', body: {'deviceIds': ids});
        expect(res.status, 400, reason: '$ids');
      }
      verifyZeroInteractions(app.db);
    });
  });

  test('a device reads what waits for it, and confirms what it received', () async {
    when(app.db.getQueue(userId: anyNamed('userId'), deviceId: anyNamed('deviceId'))).thenAnswer(
      (_) async => [
        QueuedItem(id: item, recipientDeviceId: device, kind: 'key', content: 'sealed', createdAt: DateTime.utc(2026)),
      ],
    );
    when(
      app.db.confirm(userId: anyNamed('userId'), deviceId: anyNamed('deviceId'), ids: anyNamed('ids')),
    ).thenAnswer((_) async {});

    final read = await app.send('GET', '/keys/queue?deviceId=$device');
    expect(read.status, 200);
    expect(QueuedItems.fromJson(jsonDecode(read.body) as Map).items.single.id, item);
    verify(app.db.getQueue(userId: 'u1', deviceId: device)).called(1);

    final confirmed = await app.send(
      'POST',
      '/keys/queue/confirmations',
      body: {
        'deviceId': device,
        'ids': [item],
      },
    );
    expect(confirmed.status, 204);
    verify(app.db.confirm(userId: 'u1', deviceId: device, ids: [item])).called(1);
  });
}
