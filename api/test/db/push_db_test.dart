@Tags(['db'])
library;

import 'package:heart/models/errors.dart';
import 'package:test/test.dart';

import 'db_test_utility.dart';

void main() {
  final h = _Harness();

  setUpAll(h.setupDatabase);
  tearDownAll(h.teardownDatabase);

  const topic = 'coaching.message';

  test('preferences are sparse, per topic and per relationship', () async {
    final (me, other) = (await h.seedProfile(), await h.seedProfile());
    await h.seedConnection(initiator: me, target: other);
    final connection = (await h.db.getConnections(me)).single.connectionId!;
    expect(await h.db.getPushPreferences(userId: me), isEmpty);

    await h.db.setPushPreference(userId: me, topic: topic, delivery: 'off');
    await h.db.setPushPreference(userId: me, topic: topic, delivery: 'instant', connectionId: connection);
    await h.db.setPushPreference(userId: me, topic: topic, delivery: 'instant');

    final said = await h.db.getPushPreferences(userId: me);
    expect(said, hasLength(2));
    expect(said.first.connectionId, isNull);
    expect(said.first.delivery, 'instant');
    expect(said.last.connectionId, connection);

    await h.db.clearPushPreference(userId: me, topic: topic, connectionId: connection);
    expect(await h.db.getPushPreferences(userId: me), hasLength(1));
    await h.db.clearPushPreference(userId: me, topic: topic);
    expect(await h.db.getPushPreferences(userId: me), isEmpty);
  });

  test('a preference can only be about your own relationship', () async {
    final (a, b, stranger) = (await h.seedProfile(), await h.seedProfile(), await h.seedProfile());
    await h.seedConnection(initiator: a, target: b);
    final connection = (await h.db.getConnections(a)).single.connectionId!;

    await expectLater(
      h.db.setPushPreference(userId: stranger, topic: topic, delivery: 'off', connectionId: connection),
      throwsA(isA<NotFound>()),
    );
  });

  test('the audience says what they want, and whether a block stands', () async {
    final (me, other) = (await h.seedProfile(), await h.seedProfile());
    await h.seedConnection(initiator: me, target: other);
    final connection = (await h.db.getConnections(me)).single.connectionId!;
    await h.db.registerDevice(profileId: me, platform: .ios, token: 't-$me', locale: 'ru', settings: const {});

    var audience = await h.db.getPushAudience(userId: me, topic: topic, connectionId: connection, actorId: other);
    expect(audience.devices.single, (token: 't-$me', locale: 'ru'));
    expect(audience.blocked, isFalse);
    expect(audience.forPerson, isNull);
    expect(audience.forTopic, isNull);

    await h.db.setPushPreference(userId: me, topic: topic, delivery: 'off', connectionId: connection);
    await h.db.setPushPreference(userId: me, topic: topic, delivery: 'instant');
    await h.exec('INSERT INTO blocks (blocker_id, blocked_id) VALUES (@a, @b)', {'a': other, 'b': me});

    audience = await h.db.getPushAudience(userId: me, topic: topic, connectionId: connection, actorId: other);
    expect(audience.forPerson, 'off');
    expect(audience.forTopic, 'instant');
    expect(audience.blocked, isTrue);

    audience = await h.db.getPushAudience(userId: me, topic: topic);
    expect(audience.blocked, isFalse, reason: 'with nobody it is about');
  });

  test('the audience names who it is about as their profile does', () async {
    final (me, other) = (await h.seedProfile(), await h.seedProfile());
    await h.exec("UPDATE profiles SET username = 'Alex Rivera' WHERE id = @id", {'id': other});
    expect((await h.db.getPushAudience(userId: me, topic: topic, actorId: other)).actorName, 'Alex Rivera');

    await h.exec("UPDATE profiles SET username = '  ' WHERE id = @id", {'id': other});
    expect((await h.db.getPushAudience(userId: me, topic: topic, actorId: other)).actorName, isNull);
    expect((await h.db.getPushAudience(userId: me, topic: topic)).actorName, isNull);
  });

  test('a push about a person reads what was said about them, with no relationship named', () async {
    final (me, other) = (await h.seedProfile(), await h.seedProfile());
    await h.seedConnection(initiator: me, target: other);
    final connection = (await h.db.getConnections(me)).single.connectionId!;
    await h.db.setPushPreference(userId: me, topic: 'comment.created', delivery: 'off', connectionId: connection);

    final audience = await h.db.getPushAudience(userId: me, topic: 'comment.created', actorId: other);
    expect(audience.forPerson, 'off');

    final nobody = await h.db.getPushAudience(userId: me, topic: 'comment.created');
    expect(nobody.forPerson, isNull, reason: 'with nobody it is about');
  });

  group('digests', () {
    const digest = 'coaching.workout_digest';

    /// The offset that makes it [hour] o'clock for someone now, so these tests
    /// read the same at any time of day.
    int offsetFor(int hour) {
      final minutes = ((hour - DateTime.now().toUtc().hour) % 24) * 60;
      return minutes > 840 ? minutes - 1440 : minutes;
    }

    Future<void> register(String me, String token, int? offset) {
      return h.db.registerDevice(
        profileId: me,
        platform: .ios,
        token: '$token-$me',
        locale: 'en',
        settings: const {},
        utcOffsetMinutes: offset,
      );
    }

    Future<void> queuedAgo(String me, Duration ago) async {
      await h.db.queueDigest(userId: me, topic: digest);
      await h.exec('UPDATE push_digests SET created_at = now() - @ago::interval WHERE user_id = @me', {
        'me': me,
        'ago': '${ago.inMinutes} minutes',
      });
    }

    Future<bool> claimed(String me, {required int from}) async {
      final due = await h.db.claimDueDigests(localHour: from);
      return due.any((due) => due.userId == me);
    }

    test('one is owed however much happens, and goes out once their evening starts, once', () async {
      final me = await h.seedProfile();
      await register(me, 'd', offsetFor(12));
      await h.db.queueDigest(userId: me, topic: digest);
      await queuedAgo(me, const Duration(hours: 1));

      expect(await claimed(me, from: 13), isFalse, reason: 'it is not their evening yet');
      expect(await claimed(me, from: 12), isTrue);
      expect(await claimed(me, from: 12), isFalse);
    });

    test('an hour the schedule missed is caught up later that evening', () async {
      final me = await h.seedProfile();
      await register(me, 'd', offsetFor(12));
      await queuedAgo(me, const Duration(hours: 3));

      expect(await claimed(me, from: 11), isTrue);
    });

    test('what was queued once the evening began waits for the next one', () async {
      final me = await h.seedProfile();
      await register(me, 'd', offsetFor(12));
      await queuedAgo(me, Duration.zero);
      expect(await claimed(me, from: 11), isFalse);

      await queuedAgo(me, const Duration(days: 1));
      expect(await claimed(me, from: 11), isTrue, reason: 'the next evening');
    });

    test('the device they last used decides, so two devices mean one push', () async {
      final me = await h.seedProfile();
      await register(me, 'old', offsetFor(6));
      await h.exec("UPDATE device_tokens SET last_seen_at = now() - INTERVAL '1 day' WHERE token = @t", {
        't': 'old-$me',
      });
      await register(me, 'new', offsetFor(12));
      await queuedAgo(me, const Duration(hours: 2));

      expect(await claimed(me, from: 11), isTrue);
    });

    test('a device that never said its offset says nothing of their zone', () async {
      final me = await h.seedProfile();
      // UTC is what a device with no offset would stand for, so their evening has
      // to start at an hour UTC hasn't reached, or has long passed
      final hour = switch (DateTime.now().toUtc().hour) {
        11 || 12 => 18,
        _ => 12,
      };
      await register(me, 'said', offsetFor(hour));
      await h.exec("UPDATE device_tokens SET last_seen_at = now() - INTERVAL '1 day' WHERE token = @t", {
        't': 'said-$me',
      });
      await register(me, 'silent', null);
      await queuedAgo(me, const Duration(hours: 2));

      expect(await claimed(me, from: hour - 1), isTrue);
    });

    test('a device that does not say its offset keeps the last one it said', () async {
      final me = await h.seedProfile();
      await register(me, 'k', 60);
      await register(me, 'k', null);
      final rows = await h.exec('SELECT utc_offset_minutes FROM device_tokens WHERE token = @t', {'t': 'k-$me'});
      expect(rows.first[0], 60);
    });
  });
}

class _Harness extends DatabaseTestBase;
