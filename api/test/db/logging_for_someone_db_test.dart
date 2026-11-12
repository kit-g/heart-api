@Tags(['db'])
library;

import 'package:heart/globals/config.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/models/errors.dart';
import 'package:heart/models/workouts.dart';
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

  test('only the owner and the coach who logged it are told who entered it', () async {
    final (coach, student) = await coaching();
    final peer = await h.seedProfile();
    await h.seedConnection(initiator: student, target: peer);
    final exercise = await h.seedGlobalExercise();
    final json = body(exercise);
    await logWorkoutForStudent(logging(coach, student, json), student);
    final id = json['id'] as String;

    final listed = await h.db.getWorkouts(userId: peer, targetUserId: student, limit: 5, imageUrl: imageUrl);
    expect(listed.items.single.id, id, reason: 'the peer reads the workout');
    expect((listed.items.single.loggedBy, listed.items.single.loggedByName), (null, null));
    final read = await h.db.getTargetWorkout(
      requesterId: peer,
      targetUserId: student,
      workoutId: id,
      imageUrl: imageUrl,
    );
    expect((read.loggedBy, read.loggedByName), (null, null));

    final byCoach = await h.db.getWorkouts(userId: coach, targetUserId: student, limit: 5, imageUrl: imageUrl);
    expect((byCoach.items.single.loggedBy, byCoach.items.single.loggedByName), (coach, 'u_$coach'));
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

  test('a replace or a patch by the student still says who entered it', () async {
    final (coach, student) = await coaching();
    final exercise = await h.seedGlobalExercise();
    final json = body(exercise);
    final (created, _) = await h.db.createWorkout(
      userId: student,
      body: WorkoutRequest(userId: student, body: json),
      imageUrl: imageUrl,
      loggedBy: coach,
    );
    expect(created.loggedByName, 'u_$coach', reason: 'the first answer as much as a retry');

    final id = json['id'] as String;
    final replaced = await h.db.updateWorkout(
      userId: student,
      workoutId: id,
      body: WorkoutRequest(userId: student, body: {...json, 'name': 'Renamed'}),
      imageUrl: imageUrl,
    );
    expect((replaced.loggedBy, replaced.loggedByName), (coach, 'u_$coach'));
    final patched = await h.db.patchWorkout(userId: student, workoutId: id, imageUrl: imageUrl, name: 'Again');
    expect((patched.loggedBy, patched.loggedByName), (coach, 'u_$coach'));
  });

  group('what a log may name', () {
    Future<String> program(String student, {String? coach}) async {
      final connection = switch (coach) {
        null => null,
        _ => (await h.db.getConnections(coach)).single.connectionId,
      };
      return h.insertId(
        '''
        INSERT INTO programs (user_id, name, coach_id, connection_id)
        VALUES (@s, 'Plan', @c, @connection::uuid)
        RETURNING id
        ''',
        {'s': student, 'c': coach, 'connection': connection},
      );
    }

    test('only the coach\'s own copy, so a log moves no program they can\'t write', () async {
      final (coach, student) = await coaching();
      final exercise = await h.seedGlobalExercise();
      final theirs = await program(student, coach: coach);
      final own = await program(student);

      final linked = body(exercise);
      await logWorkoutForStudent(logging(coach, student, {...linked, 'programId': theirs}), student);
      final unlinked = body(exercise);
      await logWorkoutForStudent(logging(coach, student, {...unlinked, 'programId': own}), student);

      final rows = await h.exec('SELECT id::text, program_id::text FROM workouts WHERE user_id = @s', {'s': student});
      final programs = {for (final row in rows) row[0]: row[1]};
      expect(programs[linked['id']], theirs);
      expect(programs[unlinked['id']], isNull, reason: 'the student\'s own program is no link for a coach');
    });

    test('nothing from before coaching began, without the history', () async {
      final (coach, student) = await coaching();
      final exercise = await h.seedGlobalExercise();
      await expectLater(
        logWorkoutForStudent(logging(coach, student, {...body(exercise), 'start': '2019-06-01T10:00:00Z'}), student),
        throwsA(isA<Forbidden>().having((e) => e.code, 'code', 'not_loggable')),
      );
      expect(await h.exec('SELECT 1 FROM workouts WHERE user_id = @s', {'s': student}), isEmpty);
    });

    test('a retry doesn\'t bring back what the student deleted', () async {
      final (coach, student) = await coaching();
      final exercise = await h.seedGlobalExercise();
      final json = body(exercise);
      await logWorkoutForStudent(logging(coach, student, json), student);
      await h.db.deleteWorkout(userId: student, workoutId: json['id'] as String);

      await expectLater(
        logWorkoutForStudent(logging(coach, student, json), student),
        throwsA(isA<Forbidden>().having((e) => e.code, 'code', 'not_loggable')),
      );
      expect(await h.exec('SELECT 1 FROM workouts WHERE user_id = @s', {'s': student}), isEmpty);
    });
  });

  group('a base a coach moves', () {
    Future<String> copy(String coach, String student) async {
      final connection = (await h.db.getConnections(coach)).single.connectionId;
      return h.insertId(
        '''
        INSERT INTO programs (user_id, name, coach_id, connection_id)
        VALUES (@s, 'Plan', @c, @connection::uuid)
        RETURNING id
        ''',
        {'s': student, 'c': coach, 'connection': connection},
      );
    }

    ProgramBase base(String exercise, String? workout, {String? id}) {
      return ProgramBase(
        id: id ?? uuidV7(),
        exerciseId: exercise,
        value: 100,
        workoutId: workout,
        at: DateTime.utc(2026, 10),
      );
    }

    test('goes only by a workout they logged', () async {
      final (coach, student) = await coaching();
      final exercise = await h.seedGlobalExercise();
      final program = await copy(coach, student);
      final json = body(exercise);
      await logWorkoutForStudent(logging(coach, student, json), student);
      final own = await h.seedWorkout(userId: student, start: DateTime.utc(2026), end: DateTime.utc(2026));

      final (_, created) = await h.db.createProgramBase(
        userId: student,
        programId: program,
        base: base(exercise, json['id'] as String),
        loggedBy: coach,
      );
      expect(created, isTrue);
      await expectLater(
        h.db.createProgramBase(userId: student, programId: program, base: base(exercise, own), loggedBy: coach),
        throwsA(isA<NotFound>().having((e) => e.code, 'code', 'unknown_workout')),
      );
    });

    test('a replay answers only with a base of this program, from what they can read', () async {
      final (coach, student) = await coaching();
      final exercise = await h.seedGlobalExercise();
      final program = await copy(coach, student);
      final json = body(exercise);
      await logWorkoutForStudent(logging(coach, student, json), student);
      final workout = json['id'] as String;
      final moved = base(exercise, workout);
      await h.db.createProgramBase(userId: student, programId: program, base: moved, loggedBy: coach);

      final elsewhere = await h.insertId("INSERT INTO programs (user_id, name) VALUES (@s, 'Mine') RETURNING id", {
        's': student,
      });
      final mine = base(exercise, null);
      await h.db.createProgramBase(userId: student, programId: elsewhere, base: mine);
      await expectLater(
        h.db.createProgramBase(
          userId: student,
          programId: program,
          base: base(exercise, null, id: mine.id),
          loggedBy: coach,
        ),
        throwsA(isA<Forbidden>()),
        reason: 'the id is taken, and what it holds is not handed back',
      );

      await h.db.hideWorkout(userId: student, workoutId: workout);
      await expectLater(
        h.db.createProgramBase(userId: student, programId: program, base: base(exercise, workout), loggedBy: coach),
        throwsA(isA<NotFound>()),
        reason: 'a base a hidden workout moved stays out of the coach\'s view',
      );
    });
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
