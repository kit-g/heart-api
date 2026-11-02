@Tags(['db'])
library;

import 'package:heart/models/errors.dart';
import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

import 'db_test_utility.dart';

void main() {
  final h = _Harness();

  setUpAll(h.setupDatabase);
  tearDownAll(h.teardownDatabase);

  Future<String> device(String user, {String? vouchedBy, String? signature}) async {
    final published = await h.db.publishDevice(
      userId: user,
      id: uuidV7(),
      identityKey: 'identity',
      signingKey: 'signing',
      fallbackKey: 'fallback',
      vouchedBy: vouchedBy,
      signature: signature,
    );
    return published.id;
  }

  Future<(String, String)> connected() async {
    final (a, b) = (await h.seedProfile(), await h.seedProfile());
    await h.seedConnection(initiator: a, target: b);
    return (a, b);
  }

  group('devices', () {
    test('publishing twice answers what is there', () async {
      final me = await h.seedProfile();
      final id = uuidV7();
      Future<CryptoDevice> publish(String key) {
        return h.db.publishDevice(userId: me, id: id, identityKey: key, signingKey: 's', fallbackKey: 'f');
      }

      await publish('first');
      expect((await publish('second')).identityKey, 'first');
    });

    test('someone else cannot take a device id', () async {
      final (me, other) = (await h.seedProfile(), await h.seedProfile());
      final id = await device(me);
      await expectLater(
        h.db.publishDevice(userId: other, id: id, identityKey: 'i', signingKey: 's', fallbackKey: 'f'),
        throwsA(isA<Forbidden>().having((e) => e.code, 'code', 'id_taken')),
      );
    });

    test('a signature only counts from a device of the same owner', () async {
      final (me, other) = (await h.seedProfile(), await h.seedProfile());
      final mine = await device(me);
      final theirs = await device(other);

      final vouched = await h.db.publishDevice(
        userId: me,
        id: uuidV7(),
        identityKey: 'i',
        signingKey: 's',
        fallbackKey: 'f',
        vouchedBy: mine,
        signature: 'sig',
      );
      expect(vouched.vouchedBy, mine);
      expect(vouched.signature, 'sig');

      final not = await h.db.publishDevice(
        userId: me,
        id: uuidV7(),
        identityKey: 'i',
        signingKey: 's',
        fallbackKey: 'f',
        vouchedBy: theirs,
        signature: 'sig',
      );
      expect(not.vouchedBy, isNull);
      expect(not.signature, isNull);
    });

    test('the list is for yourself and the people you share keys with', () async {
      final (a, b) = await connected();
      final stranger = await h.seedProfile();
      final id = await device(a);

      expect((await h.db.getDevices(readerId: a, ownerId: a)).single.id, id);
      expect((await h.db.getDevices(readerId: b, ownerId: a)).single.id, id);
      await expectLater(h.db.getDevices(readerId: stranger, ownerId: a), throwsA(isA<Forbidden>()));
    });

    test('a person with no devices is an empty list', () async {
      final (a, b) = await connected();
      expect(await h.db.getDevices(readerId: a, ownerId: b), isEmpty);
    });

    test('a removed device stops being listed, and loses its keys and what waited for it', () async {
      final (a, b) = await connected();
      final (mine, theirs) = (await device(a), await device(b));
      await h.db.addOneTimeKeys(userId: a, deviceId: mine, keys: {'k1': 'v1'});
      await h.db.enqueue(
        userId: b,
        id: uuidV7(),
        recipientDeviceId: mine,
        senderDeviceId: theirs,
        kind: 'key',
        content: 'sealed',
      );

      await h.db.removeDevice(userId: b, deviceId: mine);
      expect(
        await h.db.getDevices(readerId: a, ownerId: a),
        hasLength(1),
        reason: 'only the owner removes it',
      );

      await h.db.removeDevice(userId: a, deviceId: mine);
      expect(await h.db.getDevices(readerId: a, ownerId: a), isEmpty);
      final held = await h.exec('SELECT 1 FROM one_time_keys WHERE device_id = @d::uuid', {'d': mine});
      expect(held, isEmpty);
      expect(await h.db.getQueue(userId: a, deviceId: mine), isEmpty);
    });
  });

  group('single-use keys', () {
    test('a device holds at most 50, and repeating a name adds nothing', () async {
      final me = await h.seedProfile();
      final id = await device(me);
      final fifty = {for (var i = 0; i < 50; i++) 'k$i': 'v$i'};

      expect(await h.db.addOneTimeKeys(userId: me, deviceId: id, keys: fifty), 50);
      expect(await h.db.addOneTimeKeys(userId: me, deviceId: id, keys: {'k0': 'v0'}), 50);
      await expectLater(
        h.db.addOneTimeKeys(userId: me, deviceId: id, keys: {'one_more': 'v'}),
        throwsA(isA<BadRequest>().having((e) => e.code, 'code', 'key_limit')),
      );
      expect(await h.db.countOneTimeKeys(userId: me, deviceId: id), 50);
    });

    test('only on your own device', () async {
      final (me, other) = (await h.seedProfile(), await h.seedProfile());
      final id = await device(me);
      await expectLater(h.db.addOneTimeKeys(userId: other, deviceId: id, keys: {'k': 'v'}), throwsA(isA<NotFound>()));
      await expectLater(h.db.countOneTimeKeys(userId: other, deviceId: id), throwsA(isA<NotFound>()));
    });

    test('a claim takes one from each device, then the fallback answers', () async {
      final (a, b) = await connected();
      final (one, two) = (await device(a), await device(a));
      await h.db.addOneTimeKeys(userId: a, deviceId: one, keys: {'k1': 'v1'});

      final claimed = await h.db.claimKeys(claimerId: b, ownerId: a);
      expect(claimed, hasLength(2));
      expect(claimed.firstWhere((d) => d.id == one).oneTimeKey, 'v1');
      expect(claimed.firstWhere((d) => d.id == two).oneTimeKey, isNull);
      expect(claimed.firstWhere((d) => d.id == two).fallbackKey, 'fallback');

      expect(await h.db.countOneTimeKeys(userId: a, deviceId: one), 0);
      final again = await h.db.claimKeys(claimerId: b, ownerId: a);
      expect(again.firstWhere((d) => d.id == one).oneTimeKey, isNull);
    });

    test('of claims racing, no key goes out twice', () async {
      final (a, b) = await connected();
      final id = await device(a);
      await h.db.addOneTimeKeys(userId: a, deviceId: id, keys: {for (var i = 0; i < 5; i++) 'k$i': 'v$i'});

      final claims = await Future.wait([for (var i = 0; i < 8; i++) h.db.claimKeys(claimerId: b, ownerId: a)]);
      final handed = [
        for (final claim in claims)
          if (claim.single.oneTimeKey case final String key) key,
      ];
      expect(handed.toSet(), hasLength(handed.length));
    });

    test('strangers cannot claim, and a pair is limited', () async {
      final (a, b) = await connected();
      final stranger = await h.seedProfile();
      await device(a);
      await expectLater(h.db.claimKeys(claimerId: stranger, ownerId: a), throwsA(isA<Forbidden>()));

      await h.exec(
        'INSERT INTO key_claims (claimer_id, owner_id, claims) VALUES (@b, @a, 60)',
        {'a': a, 'b': b},
      );
      await expectLater(h.db.claimKeys(claimerId: b, ownerId: a), throwsA(isA<TooManyRequests>()));

      await h.exec("UPDATE key_claims SET window_start = now() - INTERVAL '2 hours' WHERE claimer_id = @b", {'b': b});
      expect(
        await h.db.claimKeys(claimerId: b, ownerId: a),
        hasLength(1),
        reason: 'the next hour starts again',
      );
    });
  });

  group('the queue', () {
    Future<void> send(String user, String from, String to, String content, {String? id, String kind = 'key'}) {
      return h.db.enqueue(
        userId: user,
        id: id ?? uuidV7(),
        recipientDeviceId: to,
        senderDeviceId: from,
        kind: kind,
        content: content,
      );
    }

    test('delivers in the order sent, until confirmed, and a confirmed item is gone', () async {
      final (a, b) = await connected();
      final (mine, theirs) = (await device(a), await device(b));
      for (var i = 0; i < 5; i++) {
        await send(a, mine, theirs, 'item-$i');
      }

      final items = await h.db.getQueue(userId: b, deviceId: theirs);
      expect(items.map((item) => item.content), [for (var i = 0; i < 5; i++) 'item-$i']);
      expect(items.first.senderDeviceId, mine);

      final again = await h.db.getQueue(userId: b, deviceId: theirs);
      expect(again, hasLength(5), reason: 'nothing goes until it is confirmed');

      await h.db.confirm(userId: b, deviceId: theirs, ids: [items.first.id, items[1].id]);
      expect((await h.db.getQueue(userId: b, deviceId: theirs)).map((item) => item.content), [
        'item-2',
        'item-3',
        'item-4',
      ]);
    });

    test('a retry delivers once', () async {
      final (a, b) = await connected();
      final (mine, theirs) = (await device(a), await device(b));
      final id = uuidV7();
      expect(
        await h.db.enqueue(
          userId: a,
          id: id,
          recipientDeviceId: theirs,
          senderDeviceId: mine,
          kind: 'key',
          content: 'x',
        ),
        isTrue,
      );
      expect(
        await h.db.enqueue(
          userId: a,
          id: id,
          recipientDeviceId: theirs,
          senderDeviceId: mine,
          kind: 'key',
          content: 'x',
        ),
        isFalse,
      );
      expect(await h.db.getQueue(userId: b, deviceId: theirs), hasLength(1));
    });

    test('only your own device reads or confirms its queue', () async {
      final (a, b) = await connected();
      final (mine, theirs) = (await device(a), await device(b));
      await send(a, mine, theirs, 'x');

      expect(await h.db.getQueue(userId: a, deviceId: theirs), isEmpty);
      final item = (await h.db.getQueue(userId: b, deviceId: theirs)).single;
      await h.db.confirm(userId: a, deviceId: theirs, ids: [item.id]);
      expect(await h.db.getQueue(userId: b, deviceId: theirs), hasLength(1));
    });

    test('you send from your own device, to someone you share keys with', () async {
      final (a, b) = await connected();
      final stranger = await h.seedProfile();
      final (mine, theirs, strangers) = (await device(a), await device(b), await device(stranger));

      await expectLater(send(a, theirs, mine, 'x'), throwsA(isA<NotFound>()));
      await expectLater(send(a, mine, strangers, 'x'), throwsA(isA<Forbidden>()));
    });

    test('a block stops it', () async {
      final (a, b) = await connected();
      final (mine, theirs) = (await device(a), await device(b));
      await h.exec('INSERT INTO blocks (blocker_id, blocked_id) VALUES (@b, @a)', {'a': a, 'b': b});
      await expectLater(send(a, mine, theirs, 'x'), throwsA(isA<Forbidden>()));
    });

    test('stops at 2000 from one device to another', () async {
      final (a, b) = await connected();
      final (mine, theirs) = (await device(a), await device(b));
      await h.exec(
        '''
        INSERT INTO device_queue (id, recipient_device_id, sender_device_id, kind, content)
        SELECT uuidv7(), @to::uuid, @from::uuid, 'key', 'x' FROM generate_series(1, 2000)
        ''',
        {'to': theirs, 'from': mine},
      );
      await expectLater(
        send(a, mine, theirs, 'x'),
        throwsA(isA<BadRequest>().having((e) => e.code, 'code', 'queue_full')),
      );
    });

    test('an ended relationship can still ask for keys', () async {
      final (a, b) = await connected();
      final (mine, theirs) = (await device(a), await device(b));
      await h.db.deleteConnection(actorId: a, targetId: b, role: .peer, domain: .fitness);
      await send(a, mine, theirs, 'x', kind: 'key_request');
      expect((await h.db.getQueue(userId: b, deviceId: theirs)).single.kind, 'key_request');
      expect(await h.db.getKeyPeers(userId: a), [b]);
    });
  });
}

class _Harness extends DatabaseTestBase;
