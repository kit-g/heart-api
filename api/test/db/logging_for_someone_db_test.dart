@Tags(['db'])
library;

import 'package:heart/globals/config.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/models/errors.dart';
import 'package:heart/routes/program_changes.dart';
import 'package:heart_models/heart_models.dart';
import 'package:mockito/mockito.dart';
import 'package:relic/relic.dart';
import 'package:test/test.dart';

import '../helpers/request.dart';
import '../mocks.mocks.dart';
import 'db_test_utility.dart';

void main() {
  final h = _Harness();

  setUpAll(h.setupDatabase);
  tearDownAll(h.teardownDatabase);

  String imageUrl(String key) => key;

  Future<(String, String)> coaching({String status = 'active'}) async {
    final (coach, student) = (await h.seedProfile(), await h.seedProfile());
    await h.exec(
      '''
      INSERT INTO connections (initiator_id, target_id, initiator_role, target_role, domain, status, accepted_at)
      VALUES (@c, @s, 'COACH', 'STUDENT', 'fitness', @status, '2020-01-01Z')
      ''',
      {'c': coach, 's': student, 'status': status},
    );
    return (coach, student);
  }

  Request logging(String coach, String student, Map<String, dynamic> body) {
    final config = MockAppConfig();
    when(config.mediaDistribution).thenReturn('cdn.test');
    return jsonRequest(path: '/accounts/$student/workouts', body: body)
      ..user = User(id: coach)
      ..config = config
      ..programChangeService = h.db
      ..coachLibraryService = h.db
      ..workoutsService = h.db;
  }

  Map<String, dynamic> body(String exercise) => {
    'id': uuidV7(),
    'name': 'In person',
    'start': '2026-10-01T10:00:00.000Z',
    'end': '2026-10-01T11:00:00.000Z',
    'exercises': [
      {
        'id': uuidV7(),
        'exercise': {'id': exercise},
        'order': 0,
        'sets': [
          {'id': uuidV7(), 'weight': 100, 'reps': 5, 'completed': true, 'order': 0},
        ],
      },
    ],
  };

  test('it is the student\'s workout, and says who entered it', () async {
    final (coach, student) = await coaching();
    final exercise = await h.seedGlobalExercise();

    await logWorkoutForStudent(logging(coach, student, body(exercise)), student);

    final page = await h.db.getWorkouts(userId: student, targetUserId: student, limit: 5, imageUrl: imageUrl);
    final workout = page.items.single;
    expect(workout.loggedBy, coach);
    expect(workout.loggedByName, 'u_$coach');
    expect(
      await h.db.getWorkouts(userId: coach, targetUserId: coach, limit: 5, imageUrl: imageUrl).then((p) => p.items),
      isEmpty,
    );

    await h.db.deleteWorkout(userId: student, workoutId: workout.id);
    final after = await h.db.getWorkouts(userId: student, targetUserId: student, limit: 5, imageUrl: imageUrl);
    expect(after.items, isEmpty, reason: 'the student can delete it');
  });

  test('a coach\'s custom exercise reaches the student, rather than being dropped', () async {
    final (coach, student) = await coaching();
    final custom = await h.insertId(
      "INSERT INTO exercises (name, category, target, user_id) VALUES (@n, 'Barbell', 'Chest', @u) RETURNING id",
      {'n': 'Coach press ${h.uid('x')}', 'u': coach},
    );

    await logWorkoutForStudent(logging(coach, student, body(custom)), student);

    final page = await h.db.getWorkouts(userId: student, targetUserId: student, limit: 5, imageUrl: imageUrl);
    final exercise = page.items.single.first.exercise;
    expect(exercise.id, isNot(custom));
    final owner = await h.exec('SELECT user_id FROM exercises WHERE id = @id::uuid', {'id': exercise.id});
    expect(owner.first[0], student);
    await h.exec('DELETE FROM workouts WHERE user_id = @s', {'s': student});
  });

  group('an id already there', () {
    test('a retry answers the same workout, once', () async {
      final (coach, student) = await coaching();
      final exercise = await h.seedGlobalExercise();
      final json = body(exercise);

      await logWorkoutForStudent(logging(coach, student, json), student);
      final again = await logWorkoutForStudent(logging(coach, student, json), student);

      expect((again as Workout).id, json['id']);
      expect(again.loggedBy, coach);
      final page = await h.db.getWorkouts(userId: student, targetUserId: student, limit: 5, imageUrl: imageUrl);
      expect(page.items, hasLength(1));
    });

    test('the student\'s own workout comes back as nothing, hidden or not', () async {
      final (coach, student) = await coaching();
      final exercise = await h.seedGlobalExercise();
      final own = await h.seedWorkout(userId: student, start: DateTime.utc(2026), end: DateTime.utc(2026));
      await h.db.hideWorkout(userId: student, workoutId: own);

      await expectLater(
        logWorkoutForStudent(logging(coach, student, {...body(exercise), 'id': own}), student),
        throwsA(isA<Forbidden>().having((e) => e.code, 'code', 'id_taken')),
      );
    });

    test('one they logged and the student hid isn\'t read back either', () async {
      final (coach, student) = await coaching();
      final exercise = await h.seedGlobalExercise();
      final json = body(exercise);
      await logWorkoutForStudent(logging(coach, student, json), student);
      await h.db.hideWorkout(userId: student, workoutId: json['id'] as String);

      await expectLater(logWorkoutForStudent(logging(coach, student, json), student), throwsA(isA<NotFound>()));
    });
  });

  test('every read of the workout says who entered it', () async {
    final (coach, student) = await coaching();
    final exercise = await h.seedGlobalExercise();
    final json = body(exercise);
    await logWorkoutForStudent(logging(coach, student, json), student);
    final id = json['id'] as String;

    final mine = await h.db.getWorkout(userId: student, workoutId: id, imageUrl: imageUrl);
    expect(mine.loggedByName, 'u_$coach');
    final theirs = await h.db.getTargetWorkout(
      requesterId: coach,
      targetUserId: student,
      workoutId: id,
      imageUrl: imageUrl,
    );
    expect(theirs.loggedBy, coach);

    for (var i = 0; ; i++) {
      final changes = await h.db.getWorkoutChanges(userId: student, imageUrl: imageUrl);
      if (changes.upserted.isNotEmpty || i == 50) {
        expect(changes.upserted.single.loggedByName, 'u_$coach');
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  });

  test('a coach\'s plan goes only on a workout they logged', () async {
    final (coach, student) = await coaching();
    final exercise = await h.seedGlobalExercise();
    final json = body(exercise);
    await logWorkoutForStudent(logging(coach, student, json), student);
    final own = await h.seedWorkout(userId: student);

    await h.db.savePlan(userId: student, workoutId: json['id'] as String, plan: {'week': 1}, loggedBy: coach);
    await expectLater(
      h.db.savePlan(userId: student, workoutId: own, plan: {'week': 1}, loggedBy: coach),
      throwsA(isA<NotFound>()),
    );
  });

  for (final (name, status) in [('paused', 'paused'), ('ended', 'severed')]) {
    test('not across a connection that is $name', () async {
      final (coach, student) = await coaching(status: status);
      final exercise = await h.seedGlobalExercise();
      await expectLater(
        logWorkoutForStudent(logging(coach, student, body(exercise)), student),
        throwsA(isA<Forbidden>()),
      );
    });
  }

  test('not for a stranger, a peer, or across a block', () async {
    final (coach, student) = await coaching();
    final stranger = await h.seedProfile();
    expect(await h.db.canLogFor(coachId: stranger, studentId: student), isFalse);
    expect(
      await h.db.canLogFor(coachId: student, studentId: coach),
      isFalse,
      reason: 'it runs one way',
    );

    final peer = await h.seedProfile();
    await h.seedConnection(initiator: peer, target: student);
    expect(await h.db.canLogFor(coachId: peer, studentId: student), isFalse);

    expect(await h.db.canLogFor(coachId: coach, studentId: student), isTrue);
    await h.exec('INSERT INTO blocks (blocker_id, blocked_id) VALUES (@s, @c)', {'s': student, 'c': coach});
    expect(await h.db.canLogFor(coachId: coach, studentId: student), isFalse);
  });
}

class _Harness extends DatabaseTestBase;
