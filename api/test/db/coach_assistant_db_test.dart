@Tags(['db'])
library;

import 'package:heart/models/errors.dart';
import 'package:test/test.dart';

import 'db_test_utility.dart';

/// What a coach's assistant reads: what the coach does, of a student who shares it
/// with the assistant, and nothing of anyone else.
void main() {
  final h = _Harness();

  setUpAll(h.setupDatabase);
  tearDownAll(h.teardownDatabase);

  String imageUrl(String key) => key;

  Future<({String coach, String student, String connection})> coached({List<String> shares = const []}) async {
    final (coach, student) = (await h.seedProfile(), await h.seedProfile());
    final rows = await h.exec(
      '''
      INSERT INTO connections (initiator_id, target_id, initiator_role, target_role, domain, status, accepted_at, shares)
      VALUES (@c, @s, 'COACH', 'STUDENT', 'fitness', 'active', '2020-01-01Z', @shares::text[])
      RETURNING id
      ''',
      {'c': coach, 's': student, 'shares': shares},
    );
    return (coach: coach, student: student, connection: rows.first[0].toString());
  }

  Future<void> share(String connection, List<String> shares) {
    return h.exec('UPDATE connections SET shares = @shares::text[] WHERE id = @id::uuid', {
      'id': connection,
      'shares': shares,
    });
  }

  Future<String> trained(String student) {
    return h.seedWorkout(
      userId: student,
      start: DateTime.now().toUtc().subtract(const Duration(days: 1)),
      end: DateTime.now().toUtc().subtract(const Duration(days: 1)),
    );
  }

  test("a student's workouts reach the coach's assistant only while they share them with it", () async {
    final (:coach, :student, :connection) = await coached();
    final workout = await trained(student);

    final coachSees = await h.db.getWorkouts(userId: coach, targetUserId: student, imageUrl: imageUrl);
    expect(coachSees.items.single.id, workout);
    await expectLater(
      h.db.getWorkouts(userId: coach, targetUserId: student, imageUrl: imageUrl, assistant: true),
      throwsA(isA<Forbidden>()),
    );
    await expectLater(
      h.db.getTargetWorkout(
        requesterId: coach,
        targetUserId: student,
        workoutId: workout,
        imageUrl: imageUrl,
        assistant: true,
      ),
      throwsA(isA<Forbidden>()),
    );

    await share(connection, ['assistant']);
    final read = await h.db.getWorkouts(userId: coach, targetUserId: student, imageUrl: imageUrl, assistant: true);
    expect(read.items.single.id, workout);
    final one = await h.db.getTargetWorkout(
      requesterId: coach,
      targetUserId: student,
      workoutId: workout,
      imageUrl: imageUrl,
      assistant: true,
    );
    expect(one.id, workout);
  });

  test("a friend's assistant reads nothing of them, and your own reads all of yours", () async {
    final (friend, me) = (await h.seedProfile(), await h.seedProfile());
    await h.seedConnection(initiator: friend, target: me);
    await trained(me);

    expect((await h.db.getWorkouts(userId: friend, targetUserId: me, imageUrl: imageUrl)).items, hasLength(1));
    await expectLater(
      h.db.getWorkouts(userId: friend, targetUserId: me, imageUrl: imageUrl, assistant: true),
      throwsA(isA<Forbidden>()),
    );
    final mine = await h.db.getWorkouts(userId: me, targetUserId: me, imageUrl: imageUrl, assistant: true);
    expect(mine.items, hasLength(1));
  });

  test('goals take both shares: the goals, and the assistant', () async {
    final (:coach, :student, :connection) = await coached(shares: ['goals']);
    await h.exec(
      "INSERT INTO goals (user_id, metric, stages) VALUES (@u, 'workouts', @s::jsonb)",
      {'u': student, 's': '[{"id": "s1", "target": 3}]'},
    );

    expect(await h.db.getTargetUserGoals(requesterId: coach, targetUserId: student), hasLength(1));
    await expectLater(
      h.db.getTargetUserGoals(requesterId: coach, targetUserId: student, assistant: true),
      throwsA(isA<Forbidden>()),
    );

    await share(connection, ['assistant']);
    await expectLater(
      h.db.getTargetUserGoals(requesterId: coach, targetUserId: student, assistant: true),
      throwsA(isA<Forbidden>()),
      reason: 'the assistant reads only what the coach does',
    );

    await share(connection, ['goals', 'assistant']);
    expect(await h.db.getTargetUserGoals(requesterId: coach, targetUserId: student, assistant: true), hasLength(1));
  });

  test("a copy the coach sent is the assistant's to read only while it is shared", () async {
    final (:coach, :student, :connection) = await coached();
    final program = await h.insertId(
      'INSERT INTO programs (user_id, name, coach_id, connection_id) VALUES (@s, @n, @c, @k::uuid) RETURNING id',
      {'s': student, 'n': 'Plan', 'c': coach, 'k': connection},
    );

    expect((await h.db.readCopy(coachId: coach, studentId: student, programId: program)).program.id, program);
    await expectLater(
      h.db.readCopy(coachId: coach, studentId: student, programId: program, assistant: true),
      throwsA(isA<Forbidden>()),
    );
    await expectLater(
      h.db.getProgramChanges(ownerId: student, programId: program, readerId: coach, assistant: true),
      throwsA(isA<Forbidden>()),
    );
    expect(await h.db.getCopies(coachId: coach, studentId: student), hasLength(1));
    expect(await h.db.getCopies(coachId: coach, studentId: student, assistant: true), isEmpty);

    await share(connection, ['assistant']);
    final read = await h.db.readCopy(coachId: coach, studentId: student, programId: program, assistant: true);
    expect(read.program.id, program);
    final changes = await h.db.getProgramChanges(
      ownerId: student,
      programId: program,
      readerId: coach,
      assistant: true,
    );
    expect(changes.items, isEmpty);
    expect(await h.db.getCopies(coachId: coach, studentId: student, assistant: true), hasLength(1));
  });

  test("the roster names a client who doesn't share, and says no more of them to the assistant", () async {
    final (:coach, :student, :connection) = await coached();
    final other = await h.seedProfile();
    await h.exec(
      '''
      INSERT INTO connections (initiator_id, target_id, initiator_role, target_role, domain, status, accepted_at, shares)
      VALUES (@c, @s, 'COACH', 'STUDENT', 'fitness', 'active', '2020-01-01Z', '{assistant}')
      ''',
      {'c': coach, 's': other},
    );
    await trained(student);
    await trained(other);
    await h.exec('UPDATE client_summaries SET last_trained_at = now() WHERE coach_id = @c', {'c': coach});

    final app = {for (final client in (await h.db.getRoster(coachId: coach)).items) client.studentId: client};
    expect(app[student]!.lastTrainedAt, isNotNull, reason: "the coach's app is told everything it was");
    expect(app[student]!.assistant, isFalse);
    expect(app[other]!.assistant, isTrue);

    final told = {
      for (final client in (await h.db.getRoster(coachId: coach, assistant: true)).items) client.studentId: client,
    };
    expect(told.keys, {student, other});
    expect(told[student]!.lastTrainedAt, isNull);
    expect(told[student]!.connectionId, connection);
    expect(told[other]!.lastTrainedAt, isNotNull);
  });

  test('the feed carries only those who share with the assistant', () async {
    final (:coach, :student, connection: _) = await coached();
    final other = await h.seedProfile();
    await h.exec(
      '''
      INSERT INTO connections (initiator_id, target_id, initiator_role, target_role, domain, status, accepted_at, shares)
      VALUES (@c, @s, 'COACH', 'STUDENT', 'fitness', 'active', '2020-01-01Z', '{assistant}')
      ''',
      {'c': coach, 's': other},
    );
    await trained(student);
    await trained(other);

    final app = await h.db.getCoachFeed(coachId: coach);
    expect({for (final item in app.items) item.studentId}, {student, other});
    final told = await h.db.getCoachFeed(coachId: coach, assistant: true);
    expect({for (final item in told.items) item.studentId}, {other});
  });

  test('someone coaches once they have had a client, or while they have a library to send from', () async {
    final (:coach, :student, :connection) = await coached();
    expect(await h.db.coaches(coach), isTrue);
    expect(await h.db.coaches(student), isFalse);

    await h.exec("UPDATE connections SET status = 'severed' WHERE id = @id::uuid", {'id': connection});
    expect(await h.db.coaches(coach), isTrue, reason: 'their former clients are still theirs to list');

    final author = await h.seedProfile();
    expect(await h.db.coaches(author), isFalse);
    await h.exec("INSERT INTO library_programs (id, coach_id, name) VALUES (uuidv7(), @c, 'Plan')", {'c': author});
    expect(await h.db.coaches(author), isTrue);
  });
}

class _Harness extends DatabaseTestBase;
