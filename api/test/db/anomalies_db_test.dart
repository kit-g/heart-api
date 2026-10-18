@Tags(['db'])
library;

import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

import 'db_test_utility.dart';

/// Anomalies against a live Postgres: what the sweep's detection writes, how
/// they page and resolve, and that an entry the user calls invalid drops out
/// of the reads every count is folded from.
///
/// Tagged `db` — skipped by the default `dart test`. Run with:
///   dart test --run-skipped -t db
void main() {
  final h = _Harness();

  setUpAll(h.setupDatabase);
  tearDownAll(h.teardownDatabase);

  /// A user with eight sessions of 100 kg for 5 on one exercise, then one of
  /// 630 kg (a pound slip) and a workout left running for 9 hours.
  Future<({String user, String exercise, String heavy, String running})> seed() async {
    final user = await h.seedProfile();
    final exercise = await h.seedGlobalExercise();
    Future<String> session(DateTime start, double weight, {Duration length = const Duration(hours: 1)}) async {
      final workout = await h.seedWorkout(userId: user, start: start, end: start.add(length));
      final we = await h.insertId(
        'INSERT INTO workout_exercises (workout_id, exercise_id, exercise_order) VALUES (@w, @e, 0) RETURNING id',
        {'w': workout, 'e': exercise},
      );
      return h.insertId(
        'INSERT INTO exercise_sets (workout_exercise_id, weight, reps, set_order, completed) '
        'VALUES (@we, @w, 5, 0, true) RETURNING id',
        {'we': we, 'w': weight},
      );
    }

    for (var day = 1; day <= 8; day++) {
      await session(DateTime.utc(2026, 9, day), 100);
    }
    final heavy = await session(DateTime.utc(2026, 9, 20), 630);
    await session(DateTime.utc(2026, 9, 21), 100, length: const Duration(hours: 9));
    final running = (await h.exec(
      'SELECT id FROM workouts WHERE user_id = @u AND started_at = @s',
      {'u': user, 's': DateTime.utc(2026, 9, 21)},
    )).single.toColumnMap()['id'].toString();
    await h.exec('SELECT _detect_anomalies(@u)', {'u': user});
    return (user: user, exercise: exercise, heavy: heavy, running: running);
  }

  test('detection lists newest first, paged, with the exercise and the workout', () async {
    final (:user, :exercise, :heavy, :running) = await seed();

    final first = await h.db.getAnomalies(userId: user, limit: 1);
    expect(first.hasMore, isTrue);
    final second = await h.db.getAnomalies(userId: user, cursor: first.items.single.id, limit: 1);
    expect(second.hasMore, isFalse);

    final all = [...first, ...second];
    final weight = all.singleWhere((anomaly) => anomaly.setId == heavy);
    expect(weight.reason, AnomalyReason.outlierWeight);
    expect(weight.exerciseId, exercise);
    expect(weight.exerciseName, isNotNull);
    expect(weight.typical, 100);
    expect(weight.observed, {'weight': 630, 'reps': 5});
    expect(weight.workoutStart, DateTime.utc(2026, 9, 20));
    final duration = all.singleWhere((anomaly) => anomaly.setId == null);
    expect(
      [duration.workoutId, duration.observed],
      [
        running,
        {'seconds': 9 * 3600},
      ],
    );

    final pending = await h.db.getPendingAnomalies(userId: user, from: DateTime.utc(2026, 9, 21));
    expect([for (final anomaly in pending) anomaly.workoutId], [running], reason: 'the window bounds the workout');

    await h.exec('DELETE FROM workouts WHERE user_id = @u', {'u': user});
  });

  test('only the owner resolves, and a resolution is listed by its status', () async {
    final (:user, exercise: _, :heavy, running: _) = await seed();
    final stranger = await h.seedProfile();
    final anomaly = (await h.db.getAnomalies(userId: user)).firstWhere((anomaly) => anomaly.setId == heavy);

    expect(
      await h.db.resolveAnomaly(userId: stranger, anomalyId: anomaly.id, status: AnomalyStatus.invalid),
      isNull,
    );
    final resolved = await h.db.resolveAnomaly(userId: user, anomalyId: anomaly.id, status: AnomalyStatus.valid);
    expect([resolved!.status, resolved.resolvedAt], [AnomalyStatus.valid, isNotNull]);
    expect([for (final a in await h.db.getAnomalies(userId: user, status: AnomalyStatus.valid)) a.id], [anomaly.id]);
    expect(await h.db.getPendingAnomalies(userId: user), hasLength(1));

    await h.exec('DELETE FROM workouts WHERE user_id = @u', {'u': user});
  });

  test('a decision can be changed, and one asked again comes back to the top', () async {
    final (:user, exercise: _, :heavy, :running) = await seed();
    await h.exec("UPDATE anomalies SET detected_at = detected_at - interval '1 day' WHERE set_id = @s", {'s': heavy});
    final top = (await h.db.getAnomalies(userId: user, limit: 1)).single;
    expect([top.workoutId, top.setId], [running, isNull], reason: 'newest found first');
    final anomaly = (await h.db.getAnomalies(userId: user)).firstWhere((anomaly) => anomaly.setId == heavy);

    final valid = await h.db.resolveAnomaly(userId: user, anomalyId: anomaly.id, status: AnomalyStatus.valid);
    final again = await h.db.resolveAnomaly(userId: user, anomalyId: anomaly.id, status: AnomalyStatus.valid);
    expect(again!.resolvedAt, valid!.resolvedAt, reason: 'the same decision again keeps when it was made');
    final changed = await h.db.resolveAnomaly(userId: user, anomalyId: anomaly.id, status: AnomalyStatus.invalid);
    expect(changed!.status, AnomalyStatus.invalid);

    await h.exec('UPDATE exercise_sets SET weight = 650 WHERE id = @s', {'s': heavy});
    await h.exec('SELECT _detect_anomalies(@u)', {'u': user});
    final raised = (await h.db.getAnomalies(userId: user, limit: 1)).single;
    expect([raised.id, raised.status], [anomaly.id, AnomalyStatus.pending], reason: 'edited and still odd');

    await h.exec('DELETE FROM workouts WHERE user_id = @u', {'u': user});
  });

  test('an invalid entry stays in the log and drops out of what is counted', () async {
    final (:user, :exercise, :heavy, :running) = await seed();
    for (final anomaly in await h.db.getAnomalies(userId: user)) {
      await h.db.resolveAnomaly(userId: user, anomalyId: anomaly.id, status: AnomalyStatus.invalid);
    }

    final sets = (await h.db.getRecordSets(userId: user, exerciseId: exercise)).single.sets;
    expect(sets.map((set) => set.weight), everyElement(100), reason: 'the 630 kg set counts for nothing');
    final history = (await h.db.getExerciseHistory(userId: user, exerciseId: exercise, limit: 50))!;
    expect(history.sessions.items.expand((session) => session.sets).map((set) => set.weight), everyElement(100));

    final spans = await h.db.getWorkoutSpans(userId: user);
    final left = spans.singleWhere((span) => span.workoutId == running);
    expect(left.duration, Duration.zero, reason: 'the workout counts, its time does not');
    expect(spans, hasLength(10));

    final stored = await h.exec('SELECT weight FROM exercise_sets WHERE id = @s', {'s': heavy});
    expect(stored.single.toColumnMap()['weight'], 630, reason: 'nothing is corrected');

    await h.exec('DELETE FROM workouts WHERE user_id = @u', {'u': user});
  });
}

class _Harness extends DatabaseTestBase;
