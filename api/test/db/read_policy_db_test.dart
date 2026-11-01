@Tags(['db'])
library;

import 'package:heart/models/errors.dart';
import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

import 'db_test_utility.dart';

/// What one person can reach of another, through every cross-user query, under
/// the relationships that decide it. docs/2026-11-01.coaching.md, *Who can read
/// what* and *Connections*.
void main() {
  final h = _Harness();

  setUpAll(h.setupDatabase);
  tearDownAll(h.teardownDatabase);

  String imageUrl(String key) => 'https://cdn.test/$key';

  Future<void> connect(
    String coach,
    String student, {
    String domain = 'fitness',
    String status = 'active',
    String initiatorRole = 'COACH',
    String targetRole = 'STUDENT',
    DateTime? acceptedAt,
    List<String> shares = const [],
  }) {
    return h.exec(
      '''
      INSERT INTO connections (initiator_id, target_id, initiator_role, target_role, domain, status, status_by, accepted_at, shares)
      VALUES (@coach, @student, @ir, @tr, @domain, @status, @coach, @accepted::timestamptz, @shares::text[])
      ''',
      {
        'coach': coach,
        'student': student,
        'ir': initiatorRole,
        'tr': targetRole,
        'domain': domain,
        'status': status,
        'accepted': acceptedAt?.toUtc(),
        'shares': shares,
      },
    );
  }

  final accepted = DateTime.utc(2026, 6);
  final before = DateTime.utc(2026, 5);
  final after = DateTime.utc(2026, 7);

  Future<Iterable<String>> workoutsSeenBy(String reader, String owner) async {
    final page = await h.db.getWorkouts(userId: reader, targetUserId: owner, limit: 50, imageUrl: imageUrl);
    return page.items.map((w) => w.id);
  }

  Future<String> workoutOf(String owner, DateTime startedAt) {
    return h.seedWorkout(userId: owner, start: startedAt, end: startedAt.add(const Duration(hours: 1)));
  }

  group('a coach reading a student', () {
    test('sees workouts from acceptance, not before', () async {
      final (coach, student) = (await h.seedProfile(), await h.seedProfile());
      final old = await workoutOf(student, before);
      final recent = await workoutOf(student, after);
      await connect(coach, student, acceptedAt: accepted);

      final seen = await workoutsSeenBy(coach, student);
      expect(seen, contains(recent));
      expect(seen, isNot(contains(old)));
      await expectLater(
        h.db.getTargetWorkout(requesterId: coach, targetUserId: student, workoutId: old, imageUrl: imageUrl),
        throwsA(isA<NotFound>()),
      );
    });

    test('sees earlier ones once the student shares their history', () async {
      final (coach, student) = (await h.seedProfile(), await h.seedProfile());
      final old = await workoutOf(student, before);
      await connect(coach, student, acceptedAt: accepted);
      expect(await workoutsSeenBy(coach, student), isEmpty);

      final updated = await h.db.changeConnectionShares(
        actorId: student,
        targetId: coach,
        role: .student,
        domain: .fitness,
        shares: {.history},
      );
      expect(updated.shares, ['history']);
      expect(await workoutsSeenBy(coach, student), contains(old));
    });

    test('a coach cannot choose what a student shares', () async {
      final (coach, student) = (await h.seedProfile(), await h.seedProfile());
      await connect(coach, student, acceptedAt: accepted);

      await expectLater(
        h.db.changeConnectionShares(
          actorId: coach,
          targetId: student,
          role: .coach,
          domain: .fitness,
          shares: {.history},
        ),
        throwsA(isA<Forbidden>()),
      );
    });

    test('never sees a hidden workout, until it is unhidden', () async {
      final (coach, student) = (await h.seedProfile(), await h.seedProfile());
      final workout = await workoutOf(student, after);
      await connect(coach, student, acceptedAt: accepted);

      await h.db.hideWorkout(userId: student, workoutId: workout, at: after);
      expect(await workoutsSeenBy(coach, student), isEmpty);
      await expectLater(
        h.db.getTargetWorkout(requesterId: coach, targetUserId: student, workoutId: workout, imageUrl: imageUrl),
        throwsA(isA<NotFound>()),
      );
      expect((await h.db.getHiddenWorkouts(userId: student)).items.single.id, workout);
      expect(await workoutsSeenBy(student, student), contains(workout), reason: 'the owner still has it');

      await h.db.unhideWorkout(userId: student, workoutId: workout);
      expect(await workoutsSeenBy(coach, student), contains(workout));
      expect((await h.db.getHiddenWorkouts(userId: student)).items, isEmpty);
    });

    test('someone else cannot hide a workout', () async {
      final (coach, student) = (await h.seedProfile(), await h.seedProfile());
      final workout = await workoutOf(student, after);
      await h.db.hideWorkout(userId: coach, workoutId: workout);
      expect((await h.db.getHiddenWorkouts(userId: student)).items, isEmpty);
    });

    test('gets no photos', () async {
      final (coach, student) = (await h.seedProfile(), await h.seedProfile());
      final workout = await workoutOf(student, after);
      await h.exec(
        'INSERT INTO workout_images (workout_id, user_id, key) VALUES (@w::uuid, @u, @k)',
        {'w': workout, 'u': student, 'k': 'photo-${h.token}'},
      );
      await connect(coach, student, acceptedAt: accepted);

      final read = await h.db.getTargetWorkout(
        requesterId: coach,
        targetUserId: student,
        workoutId: workout,
        imageUrl: imageUrl,
      );
      expect(read.images, anyOf(isNull, isEmpty));
    });

    test('a peer row in another domain adds nothing', () async {
      final (coach, student) = (await h.seedProfile(), await h.seedProfile());
      final old = await workoutOf(student, before);
      await connect(coach, student, acceptedAt: accepted);
      await connect(coach, student, domain: 'general', initiatorRole: 'PEER', targetRole: 'PEER', acceptedAt: before);

      expect(await workoutsSeenBy(coach, student), isNot(contains(old)));
    });

    test('a pause stops what is logged during it, through any domain', () async {
      final (coach, student) = (await h.seedProfile(), await h.seedProfile());
      await connect(coach, student, acceptedAt: DateTime.utc(2020));
      await connect(coach, student, domain: 'running', acceptedAt: DateTime.utc(2020));
      final earlier = await workoutOf(student, DateTime.utc(2021));

      await h.exec("UPDATE connections SET status = 'paused' WHERE initiator_id = @c AND domain = 'running'", {
        'c': coach,
      });
      // ahead of the pause whatever the two clocks say
      final during = await workoutOf(student, DateTime.now().toUtc().add(const Duration(minutes: 5)));

      final seen = await workoutsSeenBy(coach, student);
      expect(seen, contains(earlier));
      expect(seen, isNot(contains(during)));
    });

    test('reads goals only if shared', () async {
      final (coach, student) = (await h.seedProfile(), await h.seedProfile());
      await connect(coach, student, acceptedAt: accepted);
      await expectLater(
        h.db.getTargetUserGoals(requesterId: coach, targetUserId: student),
        throwsA(isA<Forbidden>()),
      );

      await h.db.changeConnectionShares(
        actorId: student,
        targetId: coach,
        role: .student,
        domain: .fitness,
        shares: {.goals},
      );
      expect(await h.db.getTargetUserGoals(requesterId: coach, targetUserId: student), isEmpty);
    });

    test('reads skips without their reason or weather, and only in scope', () async {
      final (coach, student) = (await h.seedProfile(), await h.seedProfile());
      await connect(coach, student, acceptedAt: accepted);
      await h.db.createSkip(
        userId: student,
        skip: TrainingSkip(id: uuidV7(), at: before, reason: 'sick'),
      );
      expect((await h.db.getTargetSkips(requesterId: coach, targetUserId: student)).items, isEmpty);

      final (later, _) = await h.db.createSkip(
        userId: student,
        skip: TrainingSkip(id: uuidV7(), at: after, reason: 'sick', weather: Weather(temperature: 21)),
      );
      final seen = (await h.db.getTargetSkips(requesterId: coach, targetUserId: student)).items.single;
      expect(seen.id, later.id);
      expect(seen.at.toUtc(), after);
      expect(seen.reason, isNull);
      expect(seen.weather, isNull);
    });

    test('a stranger and a peer read no skips', () async {
      final (peer, owner, stranger) = (await h.seedProfile(), await h.seedProfile(), await h.seedProfile());
      await connect(peer, owner, initiatorRole: 'PEER', targetRole: 'PEER', acceptedAt: accepted);
      for (final reader in [peer, stranger]) {
        await expectLater(h.db.getTargetSkips(requesterId: reader, targetUserId: owner), throwsA(isA<Forbidden>()));
      }
    });
  });

  group('a comment target', () {
    Future<({String ownerId, bool related, bool readable})?> access(String reader, String workout) {
      return h.db.accessOfTarget(readerId: reader, targetType: .workout, targetId: workout);
    }

    test('follows the read policy', () async {
      final (coach, student, stranger) = (await h.seedProfile(), await h.seedProfile(), await h.seedProfile());
      final old = await workoutOf(student, before);
      final recent = await workoutOf(student, after);
      await connect(coach, student, acceptedAt: accepted);

      expect((await access(student, old))?.readable, isTrue, reason: 'your own');
      expect(await access(stranger, recent), isNotNull);
      expect((await access(stranger, recent))?.related, isFalse);
      expect((await access(coach, recent))?.readable, isTrue);
      expect((await access(coach, old))?.readable, isFalse, reason: 'before acceptance');
      expect((await access(coach, old))?.related, isTrue);

      await h.db.hideWorkout(userId: student, workoutId: recent);
      expect((await access(coach, recent))?.readable, isFalse, reason: 'hidden');
    });

    test('a coach has no way to a photo, and a peer does', () async {
      final (coach, peer, owner) = (await h.seedProfile(), await h.seedProfile(), await h.seedProfile());
      final workout = await workoutOf(owner, after);
      final rows = await h.exec(
        'INSERT INTO workout_images (workout_id, user_id, key) VALUES (@w::uuid, @u, @k) RETURNING id',
        {'w': workout, 'u': owner, 'k': 'p-${h.token}'},
      );
      final image = rows.first[0].toString();
      await connect(coach, owner, acceptedAt: accepted);
      await connect(peer, owner, initiatorRole: 'PEER', targetRole: 'PEER', acceptedAt: accepted);

      Future<bool?> reach(String reader) async {
        final found = await h.db.accessOfTarget(readerId: reader, targetType: .workoutImage, targetId: image);
        return found?.readable;
      }

      expect(await reach(coach), isFalse);
      expect(await reach(peer), isTrue);
    });

    test('is missing when there is no such thing', () async {
      final reader = await h.seedProfile();
      expect(await access(reader, '01900000-0000-7000-8000-00000000dead'), isNull);
    });
  });

  group('a block', () {
    test('in one domain closes every path between the pair', () async {
      final (coach, student) = (await h.seedProfile(), await h.seedProfile());
      final workout = await workoutOf(student, after);
      await connect(coach, student, acceptedAt: accepted, shares: const ['goals']);
      await connect(coach, student, domain: 'general', initiatorRole: 'PEER', targetRole: 'PEER', acceptedAt: accepted);
      final template = await h.insertId(
        'INSERT INTO templates (user_id, name, order_index) VALUES (@u, @n, 0) RETURNING id',
        {'u': coach, 'n': 'a template'},
      );

      await h.db.changeConnectionStatus(
        actorId: student,
        targetId: coach,
        role: .peer,
        domain: .general,
        newStatus: .blocked,
      );

      await expectLater(
        h.db.getWorkouts(userId: coach, targetUserId: student, limit: 5, imageUrl: imageUrl),
        throwsA(isA<Forbidden>()),
      );
      await expectLater(
        h.db.getTargetWorkout(requesterId: coach, targetUserId: student, workoutId: workout, imageUrl: imageUrl),
        throwsA(isA<Forbidden>()),
      );
      await expectLater(h.db.getTargetUserGoals(requesterId: coach, targetUserId: student), throwsA(isA<Forbidden>()));
      await expectLater(h.db.getTargetSkips(requesterId: coach, targetUserId: student), throwsA(isA<Forbidden>()));
      expect(await h.db.areConnected(userA: coach, userB: student), isFalse);
      expect(
        (await h.db.accessOfTarget(readerId: coach, targetType: .workout, targetId: workout))?.related,
        isFalse,
      );
      await expectLater(
        h.db.shareTemplate(coachId: coach, targetUserId: student, masterTemplateId: template),
        throwsA(isA<Forbidden>()),
      );
      await expectLater(
        h.db.createConnection(initiatorId: coach, targetId: student, role: .peer, domain: .swimming),
        throwsA(isA<NotFound>()),
        reason: 'a block reads as no such person',
      );
    });
  });

  group('ending and reopening', () {
    Future<Connection?> rowOf(String actor, String other, ConnectionRole role) {
      return h.db.getConnection(actorId: actor, targetId: other, role: role, domain: .fitness);
    }

    test('the other side of a severed peer row cannot reopen it and accept their own request', () async {
      final (a, b) = (await h.seedProfile(), await h.seedProfile());
      await connect(a, b, initiatorRole: 'PEER', targetRole: 'PEER', acceptedAt: accepted);
      await h.db.deleteConnection(actorId: a, targetId: b, role: .peer, domain: .fitness);

      await h.db.changeConnectionStatus(actorId: b, targetId: a, role: .peer, domain: .fitness, newStatus: .pending);
      await expectLater(
        h.db.changeConnectionStatus(actorId: b, targetId: a, role: .peer, domain: .fitness, newStatus: .active),
        throwsA(isA<Forbidden>()),
      );
      expect(await h.db.areConnected(userA: a, userB: b), isFalse);

      final accepted_ = await h.db.changeConnectionStatus(
        actorId: a,
        targetId: b,
        role: .peer,
        domain: .fitness,
        newStatus: .active,
      );
      expect(accepted_.status, ConnectionStatus.active, reason: 'the one it was put to can answer');
    });

    test('asking again after a peer row ended puts the request to the other side', () async {
      final (a, b) = (await h.seedProfile(), await h.seedProfile());
      await connect(a, b, initiatorRole: 'PEER', targetRole: 'PEER', acceptedAt: accepted);
      await h.db.deleteConnection(actorId: b, targetId: a, role: .peer, domain: .fitness);

      final again = await h.db.createConnection(initiatorId: b, targetId: a, role: .peer, domain: .fitness);
      expect(again.status, ConnectionStatus.pending);
      expect(again.targetId, a);
      await expectLater(
        h.db.changeConnectionStatus(actorId: b, targetId: a, role: .peer, domain: .fitness, newStatus: .active),
        throwsA(isA<Forbidden>()),
      );
    });

    test('a coach row only restarts from an invitation', () async {
      final (coach, student) = (await h.seedProfile(), await h.seedProfile());
      await connect(coach, student, acceptedAt: accepted);
      await h.db.deleteConnection(actorId: student, targetId: coach, role: .student, domain: .fitness);
      expect((await rowOf(coach, student, .coach))?.status, ConnectionStatus.severed);

      for (final (actor, other, role) in [
        (coach, student, ConnectionRole.coach),
        (student, coach, ConnectionRole.student),
      ]) {
        await expectLater(
          h.db.changeConnectionStatus(
            actorId: actor,
            targetId: other,
            role: role,
            domain: .fitness,
            newStatus: .pending,
          ),
          throwsA(isA<Forbidden>()),
        );
      }
    });

    test('a pending coach row cannot be accepted outside an invitation', () async {
      final (coach, student) = (await h.seedProfile(), await h.seedProfile());
      await connect(coach, student, status: 'pending');
      await expectLater(
        h.db.changeConnectionStatus(
          actorId: student,
          targetId: coach,
          role: .student,
          domain: .fitness,
          newStatus: .active,
        ),
        throwsA(isA<Forbidden>()),
      );
    });

    test('only the student resumes a paused coach row', () async {
      final (coach, student) = (await h.seedProfile(), await h.seedProfile());
      await connect(coach, student, acceptedAt: accepted);
      await h.db.changeConnectionStatus(
        actorId: student,
        targetId: coach,
        role: .student,
        domain: .fitness,
        newStatus: .paused,
      );

      await expectLater(
        h.db.changeConnectionStatus(
          actorId: coach,
          targetId: student,
          role: .coach,
          domain: .fitness,
          newStatus: .active,
        ),
        throwsA(isA<Forbidden>()),
      );
      final resumed = await h.db.changeConnectionStatus(
        actorId: student,
        targetId: coach,
        role: .student,
        domain: .fitness,
        newStatus: .active,
      );
      expect(resumed.status, ConnectionStatus.active);
      expect(resumed.acceptedAt?.toUtc(), accepted, reason: 'a pause does not move acceptance');
    });

    test('the pair holds one row per domain, whoever asks', () async {
      final (a, b) = (await h.seedProfile(), await h.seedProfile());
      final first = await h.db.createConnection(initiatorId: a, targetId: b, role: .peer, domain: .fitness);
      final second = await h.db.createConnection(initiatorId: b, targetId: a, role: .peer, domain: .fitness);
      expect(second.connectionId, first.connectionId);

      final other = await h.db.createConnection(initiatorId: b, targetId: a, role: .peer, domain: .running);
      expect(other.connectionId, isNot(first.connectionId));
    });
  });

  group('entitlements', () {
    test('reach the profile', () async {
      final user = await h.seedProfile();
      expect((await h.db.getProfile(user))?.entitlements, isEmpty);
      await h.exec("INSERT INTO entitlements (user_id, entitlement) VALUES (@u, 'coach')", {'u': user});
      expect((await h.db.getProfile(user))?.entitlements, ['coach']);
    });
  });
}

class _Harness extends DatabaseTestBase;
