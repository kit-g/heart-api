@Tags(['db'])
library;

import 'package:heart/models/errors.dart';
import 'package:heart_models/heart_models.dart';
import 'package:postgres/postgres.dart' show Sql;
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

    test('a publish racing another of the same id answers the device, not a stranger\'s id', () async {
      final me = await h.seedProfile();
      final id = uuidV7();
      final published = await h.runBlocked(
        hold: (tx) async {
          await tx.execute(
            Sql.named(
              'INSERT INTO crypto_devices (id, user_id, identity_key, signing_key, fallback_key) '
              "VALUES (@id::uuid, @me, 'first', 's', 'f')",
            ),
            parameters: {'id': id, 'me': me},
          );
        },
        calls: [
          () => h.db.publishDevice(userId: me, id: id, identityKey: 'retry', signingKey: 's', fallbackKey: 'f'),
        ],
      );
      expect(published.single.identityKey, 'first');
    });

    test('a removed device stays removed, and says so', () async {
      final me = await h.seedProfile();
      final id = await device(me);
      await h.db.removeDevice(userId: me, deviceId: id);
      await expectLater(
        h.db.publishDevice(userId: me, id: id, identityKey: 'i', signingKey: 's', fallbackKey: 'f'),
        throwsA(isA<Forbidden>().having((e) => e.code, 'code', 'device_removed')),
      );
    });

    test('an account has at most ten devices in use, and removing one frees a slot', () async {
      final me = await h.seedProfile();
      final ten = [for (var i = 0; i < 10; i++) await device(me)];
      await expectLater(
        device(me),
        throwsA(isA<Conflict>().having((e) => e.code, 'code', 'device_limit')),
      );
      final again = await h.db.publishDevice(
        userId: me,
        id: ten.first,
        identityKey: 'x',
        signingKey: 's',
        fallbackKey: 'f',
      );
      expect(again.id, ten.first, reason: 'publishing one that is there again is no new device');

      await h.db.removeDevice(userId: me, deviceId: ten.last);
      expect(await device(me), isNotNull);
    });

    test('a device published while another is being published counts it', () async {
      final me = await h.seedProfile();
      for (var i = 0; i < 9; i++) {
        await device(me);
      }
      final results = await h.runBlocked(
        hold: (tx) async {
          await tx.execute(
            Sql.named("SELECT pg_advisory_xact_lock(hashtext('crypto_devices:' || @me))"),
            parameters: {'me': me},
          );
          await tx.execute(
            Sql.named(
              'INSERT INTO crypto_devices (id, user_id, identity_key, signing_key, fallback_key) '
              "VALUES (@id::uuid, @me, 'i', 's', 'f')",
            ),
            parameters: {'id': uuidV7(), 'me': me},
          );
        },
        calls: [() => device(me).then<Object>((id) => id, onError: (Object e) => e)],
      );
      expect(results.single, isA<Conflict>().having((e) => e.code, 'code', 'device_limit'));
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

    test('a published device is vouched for once, by another device of the same owner in use', () async {
      final (me, other) = (await h.seedProfile(), await h.seedProfile());
      final (trusted, fresh, another, theirs) = (
        await device(me),
        await device(me),
        await device(me),
        await device(other),
      );
      Future<({CryptoDevice device, bool changed})> vouch(String by, {String signature = 'sig', String? as}) {
        return h.db.vouchForDevice(userId: as ?? me, deviceId: fresh, vouchedBy: by, signature: signature);
      }

      for (final by in [theirs, fresh, uuidV7()]) {
        await expectLater(vouch(by), throwsA(isA<BadRequest>()), reason: 'not another device of mine');
      }
      await expectLater(vouch(trusted, as: other), throwsA(isA<NotFound>()), reason: 'not their device');

      final first = await vouch(trusted);
      expect(first.changed, isTrue);
      expect((first.device.vouchedBy, first.device.signature), (trusted, 'sig'));

      final again = await vouch(trusted);
      expect(again.changed, isFalse, reason: 'the same vouch again is a retry');
      expect(again.device.vouchedBy, trusted);

      await expectLater(
        vouch(another),
        throwsA(isA<Conflict>().having((e) => e.code, 'code', 'already_vouched')),
      );
      await expectLater(vouch(trusted, signature: 'other'), throwsA(isA<Conflict>()));
      expect((await h.db.getDevices(readerId: me, ownerId: me)).firstWhere((d) => d.id == fresh).signature, 'sig');
    });

    test('a removed device can neither be vouched for nor vouch', () async {
      final me = await h.seedProfile();
      final (kept, gone) = (await device(me), await device(me));
      await h.db.removeDevice(userId: me, deviceId: gone);

      await expectLater(
        h.db.vouchForDevice(userId: me, deviceId: gone, vouchedBy: kept, signature: 's'),
        throwsA(isA<NotFound>()),
      );
      await expectLater(
        h.db.vouchForDevice(userId: me, deviceId: kept, vouchedBy: gone, signature: 's'),
        throwsA(isA<BadRequest>()),
      );
    });

    test('of two vouches racing, one lands and the other is told', () async {
      final me = await h.seedProfile();
      final (one, two, fresh) = (await device(me), await device(me), await device(me));
      final results = await h.runBlocked(
        hold: (tx) async {
          await tx.execute(
            Sql.named(
              'UPDATE crypto_devices SET vouched_by = @one::uuid, signature = \'first\' WHERE id = @fresh::uuid',
            ),
            parameters: {'one': one, 'fresh': fresh},
          );
        },
        calls: [
          () => h.db
              .vouchForDevice(userId: me, deviceId: fresh, vouchedBy: two, signature: 'second')
              .then<Object>((result) => result, onError: (Object e) => e),
          () => h.db
              .vouchForDevice(userId: me, deviceId: fresh, vouchedBy: one, signature: 'first')
              .then<Object>((result) => result, onError: (Object e) => e),
        ],
      );
      expect(results.first, isA<Conflict>());
      expect(results.last, isA<({CryptoDevice device, bool changed})>().having((r) => r.changed, 'changed', isFalse));
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

      await expectLater(h.db.removeDevice(userId: b, deviceId: mine), throwsA(isA<NotFound>()));
      expect(
        await h.db.getDevices(readerId: a, ownerId: a),
        hasLength(1),
        reason: 'only the owner removes it',
      );

      await h.db.removeDevice(userId: a, deviceId: mine);
      expect(await h.db.getDevices(readerId: a, ownerId: a), isEmpty);
      await expectLater(
        h.db.removeDevice(userId: a, deviceId: mine),
        throwsA(isA<NotFound>()),
        reason: 'nothing changed, so nobody is told',
      );
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

    test('two uploads at once still stop at 50', () async {
      final me = await h.seedProfile();
      final id = await device(me);
      final uploads = await h.runBlocked(
        hold: (tx) async {
          await tx.execute(
            Sql.named('SELECT id FROM crypto_devices WHERE id = @id::uuid FOR UPDATE'),
            parameters: {'id': id},
          );
          await tx.execute(
            Sql.named(
              'INSERT INTO one_time_keys (device_id, key_id, key) '
              "SELECT @id::uuid, 'first-' || n, 'v' FROM generate_series(1, 30) n",
            ),
            parameters: {'id': id},
          );
        },
        calls: [
          () => h.db
              .addOneTimeKeys(userId: me, deviceId: id, keys: {for (var i = 0; i < 30; i++) 'second-$i': 'v'})
              .then<Object>((count) => count, onError: (Object e) => e),
        ],
      );
      expect(uploads.single, isA<BadRequest>().having((e) => e.code, 'code', 'key_limit'));
      expect(await h.db.countOneTimeKeys(userId: me, deviceId: id), 30);
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

    test('a claim can take keys only from the devices it names', () async {
      final (a, b) = await connected();
      final (one, two, three) = (await device(a), await device(a), await device(a));
      for (final id in [one, two, three]) {
        await h.db.addOneTimeKeys(userId: a, deviceId: id, keys: {'k': 'v-$id'});
      }
      final removed = await device(a);
      await h.db.removeDevice(userId: a, deviceId: removed);
      final strangers = await device(await h.seedProfile());

      final claimed = await h.db.claimKeys(claimerId: b, ownerId: a, deviceIds: [two, removed, strangers]);
      expect(claimed.map((d) => d.id), [two], reason: 'a removed device or someone else\'s is left out');
      expect(claimed.single.oneTimeKey, 'v-$two');
      for (final (id, left) in [(one, 1), (two, 0), (three, 1)]) {
        expect(await h.db.countOneTimeKeys(userId: a, deviceId: id), left);
      }
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
      expect(items.first.senderUserId, a, reason: 'the account the server knows sent it');

      final again = await h.db.getQueue(userId: b, deviceId: theirs);
      expect(again, hasLength(5), reason: 'nothing goes until it is confirmed');

      await h.db.confirm(userId: b, deviceId: theirs, ids: [items.first.id, items[1].id]);
      expect((await h.db.getQueue(userId: b, deviceId: theirs)).map((item) => item.content), [
        'item-2',
        'item-3',
        'item-4',
      ]);
    });

    test('an arrival wakes the recipient\'s account, at most once a minute for a device', () async {
      final (a, b) = await connected();
      final (mine, theirs, another) = (await device(a), await device(b), await device(b));
      Future<String?> notify(String to, {String? id}) async {
        final (delivered: _, :notify) = await h.db.enqueue(
          userId: a,
          id: id ?? uuidV7(),
          recipientDeviceId: to,
          senderDeviceId: mine,
          kind: 'key',
          content: 'x',
        );
        return notify;
      }

      final first = uuidV7();
      expect(await notify(theirs, id: first), b);
      expect(await notify(theirs), isNull, reason: 'something already arrived this minute');
      expect(await notify(theirs, id: first), isNull, reason: 'a retry is nothing new');
      expect(await notify(another), b, reason: 'another device has its own minute');

      await h.exec(
        "UPDATE device_queue SET created_at = now() - INTERVAL '2 minutes' WHERE recipient_device_id = @to::uuid",
        {'to': theirs},
      );
      expect(await notify(theirs), b, reason: 'still waiting a minute later, so it asks again');
    });

    test('a retry delivers once', () async {
      final (a, b) = await connected();
      final (mine, theirs) = (await device(a), await device(b));
      final id = uuidV7();
      for (final expected in [true, false]) {
        final sent = await h.db.enqueue(
          userId: a,
          id: id,
          recipientDeviceId: theirs,
          senderDeviceId: mine,
          kind: 'key',
          content: 'x',
        );
        expect(sent.delivered, expected);
      }
      expect(await h.db.getQueue(userId: b, deviceId: theirs), hasLength(1));
    });

    test('a retry after the item was confirmed delivers nothing again', () async {
      final (a, b) = await connected();
      final (mine, theirs) = (await device(a), await device(b));
      final id = uuidV7();
      Future<bool> enqueue() async {
        final (:delivered, notify: _) = await h.db.enqueue(
          userId: a,
          id: id,
          recipientDeviceId: theirs,
          senderDeviceId: mine,
          kind: 'key',
          content: 'x',
        );
        return delivered;
      }

      expect(await enqueue(), isTrue);
      await h.db.confirm(userId: b, deviceId: theirs, ids: [id]);
      expect(await enqueue(), isFalse);
      expect(await h.db.getQueue(userId: b, deviceId: theirs), isEmpty);
    });

    test('an id is one item: another pair can\'t reuse it, and a stranger learns nothing of it', () async {
      final (a, b) = await connected();
      final stranger = await h.seedProfile();
      final (mine, theirs, another, strangers) = (
        await device(a),
        await device(b),
        await device(b),
        await device(stranger),
      );
      final id = uuidV7();
      await send(a, mine, theirs, 'x', id: id);

      await expectLater(
        send(a, mine, another, 'y', id: id),
        throwsA(isA<Forbidden>().having((e) => e.code, 'code', 'id_taken')),
      );
      await expectLater(send(stranger, strangers, theirs, 'z', id: id), throwsA(isA<Forbidden>()));
      expect(await h.db.getQueue(userId: b, deviceId: another), isEmpty);
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

    test('a block stops what was already waiting, too', () async {
      final (a, b) = await connected();
      final (mine, theirs) = (await device(a), await device(b));
      await send(a, mine, theirs, 'x');
      await h.exec('INSERT INTO blocks (blocker_id, blocked_id) VALUES (@b, @a)', {'a': a, 'b': b});
      expect(await h.db.getQueue(userId: b, deviceId: theirs), isEmpty);
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

    test('an ended relationship asked again, or declined again, still had one', () async {
      final (a, b) = await connected();
      final (mine, theirs) = (await device(a), await device(b));
      await h.exec("UPDATE connections SET accepted_at = now(), status = 'pending' WHERE initiator_id = @a", {'a': a});
      await send(a, mine, theirs, 'x', kind: 'key_request');
      expect(await h.db.getDevices(readerId: a, ownerId: b), hasLength(1));
      expect(await h.db.getKeyPeers(userId: a), [b]);

      await h.exec("UPDATE connections SET status = 'declined' WHERE initiator_id = @a", {'a': a});
      expect(await h.db.getKeyPeers(userId: b), [a]);
    });

    test('a block leaves someone out of who is told', () async {
      final (a, b) = await connected();
      await h.exec('UPDATE connections SET accepted_at = now() WHERE initiator_id = @a', {'a': a});
      expect(await h.db.getKeyPeers(userId: a), [b]);
      await h.exec('INSERT INTO blocks (blocker_id, blocked_id) VALUES (@b, @a)', {'a': a, 'b': b});
      expect(await h.db.getKeyPeers(userId: a), isEmpty);
    });
  });
}

class _Harness extends DatabaseTestBase;
