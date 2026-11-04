@Tags(['db'])
library;

import 'package:heart/globals/globals.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/routes/roster.dart';
import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

import '../helpers/request.dart';
import 'db_test_utility.dart';

void main() {
  final h = _Harness();

  setUpAll(h.setupDatabase);
  tearDownAll(h.teardownDatabase);

  Future<(String, String, String)> client({String? coach, DateTime? acceptedAt}) async {
    final (c, student) = (coach ?? await h.seedProfile(), await h.seedProfile());
    final rows = await h.exec(
      '''
      INSERT INTO connections (initiator_id, target_id, initiator_role, target_role, domain, status, accepted_at)
      VALUES (@c, @s, 'COACH', 'STUDENT', 'fitness', 'active', @at::timestamptz)
      RETURNING id
      ''',
      {'c': c, 's': student, 'at': (acceptedAt ?? DateTime.utc(2020)).toIso8601String()},
    );
    return (c, student, rows.first[0].toString());
  }

  Future<Page<ClientSummary>> roster(
    String coach, {
    String? reason,
    bool former = false,
    String? cursor,
    int limit = 50,
    bool byNeed = true,
  }) async {
    final req = bareRequest()
      ..user = User(id: coach)
      ..rosterService = h.db
      ..programChangeService = h.db
      ..programService = h.db;
    await refreshRoster(req);
    return h.db.getRoster(coachId: coach, reason: reason, former: former, cursor: cursor, limit: limit);
  }

  Future<String> trained(String student, {DateTime? at, String? note}) {
    final start = at ?? DateTime.now().toUtc().subtract(const Duration(hours: 1));
    return h.insertId(
      'INSERT INTO workouts (user_id, name, started_at, completed_at, note) VALUES (@u, @n, @s, @s, @note) RETURNING id',
      {'u': student, 'n': 'Trained', 's': start, 'note': note},
    );
  }

  test('a summary says what the coach can see', () async {
    final (coach, student, _) = await client();
    final at = DateTime.now().toUtc().subtract(const Duration(days: 2));
    await trained(student, at: at);

    final summary = (await roster(coach)).items.single;
    expect(summary.studentId, student);
    expect(summary.status, 'active');
    expect(summary.recent, hasLength(1));
    expect(summary.lastTrainedAt?.difference(at).inSeconds.abs(), lessThan(2));
    expect(summary.reasons, isEmpty);
    expect(summary.toMap().containsKey('email'), isFalse);
  });

  group('a reason', () {
    test('a note, until the coach has looked', () async {
      final (coach, student, connection) = await client();
      await trained(student, note: 'knees felt fine');
      expect((await roster(coach)).items.single.reasons, ['note']);

      await h.db.markReviewed(coachId: coach, connectionId: connection);
      expect((await roster(coach)).items.single.reasons, isEmpty);

      await trained(student, at: DateTime.now().toUtc().add(const Duration(minutes: 5)), note: 'and again');
      expect((await roster(coach)).items.single.reasons, ['note']);
    });

    test('a gap, which clears when they train', () async {
      final (coach, student, _) = await client();
      await trained(student, at: DateTime.now().toUtc().subtract(const Duration(days: 8)));
      expect((await roster(coach)).items.single.reasons, ['gap']);
      await trained(student);
      expect((await roster(coach)).items.single.reasons, isEmpty);
    });

    test('nobody is a gap for a week after accepting', () async {
      final (coach, _, _) = await client(acceptedAt: DateTime.now().toUtc());
      expect((await roster(coach)).items.single.reasons, isEmpty);
    });

    test('lighter than planned, and following a lighter week is not', () async {
      final (coach, student, _) = await client();
      final exercise = await h.seedGlobalExercise();
      final workout = await trained(student);
      final we = await h.insertId(
        'INSERT INTO workout_exercises (workout_id, exercise_id, exercise_order) VALUES (@w::uuid, @e::uuid, 0) RETURNING id',
        {'w': workout, 'e': exercise},
      );
      final set = await h.insertId(
        '''
        INSERT INTO exercise_sets (workout_exercise_id, weight, reps, completed, set_order)
        VALUES (@we::uuid, 50, 5, true, 0)
        RETURNING id
        ''',
        {'we': we},
      );
      await h.db.savePlan(
        userId: student,
        workoutId: workout,
        plan: {
          'exercises': [
            {
              'sets': [
                {'weight': 50, 'setId': set},
              ],
            },
          ],
        },
      );
      expect((await roster(coach)).items.single.reasons, isEmpty);

      await h.exec('UPDATE exercise_sets SET weight = 40 WHERE id = @s::uuid', {'s': set});
      await h.exec('UPDATE workouts SET note = NULL WHERE id = @w::uuid', {'w': workout});
      expect((await roster(coach)).items.single.reasons, ['lighter']);
    });
  });

  test('a plan of the wrong shape, however it got there, takes nothing down', () async {
    final (coach, student, _) = await client();
    final workout = await trained(student);
    await h.exec(
      '''INSERT INTO workout_plans (workout_id, plan) VALUES (@w::uuid, '{"exercises": {"x": 1}}')''',
      {'w': workout},
    );
    final summary = (await roster(coach)).items.single;
    expect(summary.reasons, isEmpty);
    expect(summary.recent, hasLength(1));
  });

  test('working one out over a change still being written leaves it dirty', () async {
    final (coach, student, _) = await client();
    final read = (await h.db.getDirtySummaries(coachId: coach)).single;

    await trained(student);
    await h.db.refreshSummary(
      connectionId: read.connectionId,
      coachId: read.coachId,
      studentId: read.studentId,
      generation: read.generation,
      ending: false,
    );
    expect(await h.db.getDirtySummaries(coachId: coach), hasLength(1), reason: 'it read from before the workout');

    final again = (await h.db.getDirtySummaries(coachId: coach)).single;
    await h.db.refreshSummary(
      connectionId: again.connectionId,
      coachId: again.coachId,
      studentId: again.studentId,
      generation: again.generation,
      ending: false,
    );
    expect(await h.db.getDirtySummaries(coachId: coach), isEmpty);
  });

  group('what it can\'t see', () {
    test('a hidden workout moves nothing, and hiding one puts it back', () async {
      final (coach, student, _) = await client();
      final old = DateTime.now().toUtc().subtract(const Duration(days: 8));
      await trained(student, at: old);
      final hidden = await trained(student, note: 'a hidden note');

      expect((await roster(coach)).items.single.reasons, ['note']);

      await h.db.hideWorkout(userId: student, workoutId: hidden);
      final summary = (await roster(coach)).items.single;
      expect(summary.reasons, ['gap']);
      expect(summary.recent, hasLength(1));

      await h.db.unhideWorkout(userId: student, workoutId: hidden);
      expect((await roster(coach)).items.single.reasons, ['note']);
    });

    test('a workout before they connected is not counted', () async {
      final (coach, student, _) = await client(acceptedAt: DateTime.now().toUtc());
      await trained(student, at: DateTime.utc(2021), note: 'long ago');
      final summary = (await roster(coach)).items.single;
      expect(summary.lastTrainedAt, isNull);
      expect(summary.reasons, isEmpty);
    });
  });

  group('the list', () {
    test('those who need a word first, filtered by reason, paged', () async {
      final coach = await h.seedProfile();
      final fine = <String>[];
      for (var i = 0; i < 3; i++) {
        final (_, student, _) = await client(coach: coach);
        await trained(student);
        fine.add(student);
      }
      final (_, needy, _) = await client(coach: coach);
      await trained(needy, note: 'hello');

      final first = await roster(coach, limit: 2);
      expect(first.items.first.studentId, needy);
      expect(first.hasMore, isTrue);

      final last = first.items.last;
      final next = await roster(coach, limit: 2, cursor: '${last.reasons.isEmpty ? 1 : 0}:${last.connectionId}');
      expect(next.items, hasLength(2));
      expect({...first.items, ...next.items}.map((each) => each.studentId).toSet(), {...fine, needy});

      expect((await roster(coach, reason: 'note')).items.single.studentId, needy);
      expect(await roster(coach, reason: 'gap').then((page) => page.items), isEmpty);
    });

    test('someone else\'s clients are not there, and nor is the student\'s own side', () async {
      final (coach, student, connection) = await client();
      final other = await h.seedProfile();
      expect((await roster(other)).items, isEmpty);
      expect((await roster(student)).items, isEmpty);

      await h.db.markReviewed(coachId: other, connectionId: connection);
      final reviewed = await h.exec('SELECT reviewed_at FROM client_summaries WHERE connection_id = @c::uuid', {
        'c': connection,
      });
      expect(reviewed.first[0], isNull);
      expect((await roster(coach)).items, hasLength(1));
    });

    test('a former client is on a list of their own, as who and when', () async {
      final (coach, student, _) = await client();
      await trained(student, note: 'a note');
      await roster(coach);
      await h.db.deleteConnection(actorId: student, targetId: coach, role: .student, domain: .fitness);

      expect((await roster(coach)).items, isEmpty);
      final former = (await roster(coach, former: true)).items.single;
      expect(former.status, 'severed');
      expect(former.acceptedAt, isNotNull);
      expect(former.lastTrainedAt, isNull);
      expect(former.recent, isEmpty);
      expect(former.reasons, isEmpty);
    });
  });

  group('the feed', () {
    test('finished workouts and skips, newest first, without what it can\'t see', () async {
      final (coach, student, _) = await client();
      final older = await trained(student, at: DateTime.now().toUtc().subtract(const Duration(days: 3)));
      final hidden = await trained(student, at: DateTime.now().toUtc().subtract(const Duration(days: 2)));
      await h.db.hideWorkout(userId: student, workoutId: hidden);
      await h.db.createSkip(
        userId: student,
        skip: TrainingSkip(id: uuidV7(), at: DateTime.now().toUtc().subtract(const Duration(days: 1)), reason: 'sick'),
      );

      final items = (await h.db.getCoachFeed(coachId: coach)).items;
      expect(items.map((each) => each.kind), ['skip', 'workout']);
      expect(items.last.id, older);
      expect(items.first.toMap().toString(), isNot(contains('sick')));
    });

    test('pages', () async {
      final (coach, student, _) = await client();
      for (var i = 1; i <= 3; i++) {
        await trained(student, at: DateTime.now().toUtc().subtract(Duration(days: i)));
      }
      final first = await h.db.getCoachFeed(coachId: coach, limit: 2);
      expect(first.items, hasLength(2));
      expect(first.hasMore, isTrue);
      final next = await h.db.getCoachFeed(coachId: coach, limit: 2, cursor: first.items.last.cursor);
      expect(next.items, hasLength(1));
    });

    test('a former client\'s drop out, and so does someone else\'s', () async {
      final (coach, student, _) = await client();
      await trained(student);
      await h.db.deleteConnection(actorId: coach, targetId: student, role: .coach, domain: .fitness);
      expect((await h.db.getCoachFeed(coachId: coach)).items, isEmpty);
    });
  });

  test('a finished workout owes the coach one daily push, however many', () async {
    final (coach, student, _) = await client();
    await trained(student);
    await trained(student);
    final owed = await h.exec('SELECT topic FROM push_digests WHERE user_id = @c', {'c': coach});
    expect(owed.single[0], 'coaching.workout_digest');
  });
}

class _Harness extends DatabaseTestBase;
