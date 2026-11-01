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

  group('digests', () {
    int localHourFor(int offsetMinutes) => DateTime.now().toUtc().add(Duration(minutes: offsetMinutes)).hour;

    test('one is owed however much happens, and goes out at their hour, once', () async {
      final me = await h.seedProfile();
      await h.db.registerDevice(
        profileId: me,
        platform: .ios,
        token: 'd-$me',
        locale: 'en',
        settings: const {},
        utcOffsetMinutes: 120,
      );
      await h.db.queueDigest(userId: me, topic: 'coaching.workout_digest');
      await h.db.queueDigest(userId: me, topic: 'coaching.workout_digest');

      final notYet = await h.db.claimDueDigests(localHour: (localHourFor(120) + 6) % 24);
      expect(notYet.where((due) => due.userId == me), isEmpty);

      final due = await h.db.claimDueDigests(localHour: localHourFor(120));
      expect(due.where((due) => due.userId == me), hasLength(1));

      final again = await h.db.claimDueDigests(localHour: localHourFor(120));
      expect(again.where((due) => due.userId == me), isEmpty);
    });

    test('the device they last used decides, so two devices mean one push', () async {
      final me = await h.seedProfile();
      await h.db.registerDevice(
        profileId: me,
        platform: .ios,
        token: 'old-$me',
        locale: 'en',
        settings: const {},
        utcOffsetMinutes: 300,
      );
      await h.exec("UPDATE device_tokens SET last_seen_at = now() - INTERVAL '1 day' WHERE token = @t", {
        't': 'old-$me',
      });
      await h.db.registerDevice(
        profileId: me,
        platform: .android,
        token: 'new-$me',
        locale: 'en',
        settings: const {},
        utcOffsetMinutes: -300,
      );
      await h.db.queueDigest(userId: me, topic: 'coaching.workout_digest');

      final atOld = await h.db.claimDueDigests(localHour: localHourFor(300));
      expect(atOld.where((due) => due.userId == me), isEmpty);
      final atNew = await h.db.claimDueDigests(localHour: localHourFor(-300));
      expect(atNew.where((due) => due.userId == me), hasLength(1));
    });

    test('a device that does not say its offset keeps the last one it said', () async {
      final me = await h.seedProfile();
      Future<void> register(int? offset) {
        return h.db.registerDevice(
          profileId: me,
          platform: .ios,
          token: 'k-$me',
          locale: 'en',
          settings: const {},
          utcOffsetMinutes: offset,
        );
      }

      await register(60);
      await register(null);
      final rows = await h.exec('SELECT utc_offset_minutes FROM device_tokens WHERE token = @t', {'t': 'k-$me'});
      expect(rows.first[0], 60);
    });
  });
}

class _Harness extends DatabaseTestBase;
