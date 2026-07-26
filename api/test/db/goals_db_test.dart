@Tags(['db'])
library;

import 'package:heart/models/errors.dart';
import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

import 'db_test_utility.dart';

/// Full integration coverage of the `GoalService` query strings against a live
/// Postgres: list/create/update/delete plus the stage-achievement update, and the
/// owner-scoping / missing-row branches the SQL encodes.
///
/// Tagged `db` — skipped by the default `dart test`. Run with:
///   dart test --run-skipped -t db
void main() {
  final h = _Harness();

  late String ownerId;
  late String strangerId;
  late String listOwnerId; // isolated, so getGoals counts aren't polluted

  const missingId = '00000000-0000-7000-8000-000000000000';

  /// A recurring frequency goal: `workouts` metric carries no exercise and, being
  /// recurring, exactly one standing stage (per `goals_cadence_stages_check`).
  Goal workoutsGoal({num target = 3, GoalCadence cadence = GoalCadence.week}) {
    return Goal(
      metric: GoalMetric.workouts,
      cadence: cadence,
      stages: [GoalStage(target: target)],
    );
  }

  /// A per-exercise milestone ladder (no cadence → multiple rungs allowed).
  Goal ladderGoal(String exerciseId, {List<num> targets = const [100, 120]}) {
    return Goal(
      metric: GoalMetric.topSetWeight,
      exerciseId: exerciseId,
      stages: [for (final t in targets) GoalStage(target: t)],
    );
  }

  setUpAll(() async {
    await h.setupDatabase();
    ownerId = await h.seedProfile();
    strangerId = await h.seedProfile();
    listOwnerId = await h.seedProfile();
  });

  tearDownAll(h.teardownDatabase);

  group('getGoals', () {
    test('returns only the owner non-archived goals', () async {
      final owner = await h.seedProfile();
      await h.db.createGoal(workoutsGoal(target: 2), owner);
      await h.db.createGoal(workoutsGoal(target: 5), owner);

      final goals = (await h.db.getGoals(owner)).toList();
      expect(goals, hasLength(2));
      expect(goals.every((g) => !g.archived), isTrue);
    });

    test('excludes archived goals', () async {
      final created = await h.db.createGoal(workoutsGoal(), listOwnerId);
      await h.db.updateGoal(
        created.id!,
        created.copyWith(archived: true),
        listOwnerId,
      );

      final goals = await h.db.getGoals(listOwnerId);
      expect(goals.map((g) => g.id), isNot(contains(created.id)));
    });

    test('another user does not see the owner goals', () async {
      final created = await h.db.createGoal(workoutsGoal(), ownerId);
      final theirs = await h.db.getGoals(strangerId);
      expect(theirs.map((g) => g.id), isNot(contains(created.id)));
    });
  });

  group('createGoal', () {
    test('persists a recurring workouts goal and mints a stage id', () async {
      final created = await h.db.createGoal(workoutsGoal(target: 4), ownerId);

      expect(created.id, isNotNull);
      expect(created.metric, GoalMetric.workouts);
      expect(created.exerciseId, isNull);
      expect(created.cadence, GoalCadence.week);
      expect(created.archived, isFalse);
      expect(created.createdAt, isNotNull);
      expect(created.stages, hasLength(1));
      expect(created.stages.single.id, isNotNull); // minted server-side
      expect(created.stages.single.target, 4);
    });

    test('persists a per-exercise ladder, minting a distinct id per stage', () async {
      final exerciseId = await h.seedGlobalExercise();
      final created = await h.db.createGoal(ladderGoal(exerciseId), ownerId);

      expect(created.metric, GoalMetric.topSetWeight);
      expect(created.exerciseId, exerciseId);
      expect(created.cadence, isNull);
      expect(created.stages, hasLength(2));
      final ids = created.stages.map((s) => s.id).toSet();
      expect(ids, hasLength(2)); // both minted, both distinct
      expect(ids.contains(null), isFalse);
    });
  });

  group('updateGoal', () {
    test('replaces the goal fields for the owner', () async {
      final created = await h.db.createGoal(workoutsGoal(target: 3), ownerId);

      final updated = await h.db.updateGoal(
        created.id!,
        created.copyWith(cadence: GoalCadence.month, stages: [GoalStage(target: 6)]),
        ownerId,
      );

      expect(updated.id, created.id);
      expect(updated.cadence, GoalCadence.month);
      expect(updated.stages.single.target, 6);
    });

    test('throws NotFound updating a goal owned by another user', () async {
      final created = await h.db.createGoal(workoutsGoal(), ownerId);
      await expectLater(
        h.db.updateGoal(created.id!, created.copyWith(archived: true), strangerId),
        throwsA(isA<NotFound>()),
      );
    });

    test('throws NotFound for a missing goal id', () async {
      await expectLater(
        h.db.updateGoal(missingId, workoutsGoal(), ownerId),
        throwsA(isA<NotFound>()),
      );
    });
  });

  group('deleteGoal', () {
    test('the owner deletes their goal', () async {
      final created = await h.db.createGoal(workoutsGoal(), ownerId);
      await h.db.deleteGoal(created.id!, ownerId);

      final goals = await h.db.getGoals(ownerId);
      expect(goals.map((g) => g.id), isNot(contains(created.id)));
    });

    test('deleting a goal owned by another user is a no-op', () async {
      final created = await h.db.createGoal(workoutsGoal(), ownerId);
      await h.db.deleteGoal(created.id!, strangerId);

      final goals = await h.db.getGoals(ownerId);
      expect(goals.map((g) => g.id), contains(created.id)); // still there
    });
  });

  group('markStageAchieved', () {
    late Goal goal;
    late String firstStageId;
    late String secondStageId;

    setUp(() async {
      final exerciseId = await h.seedGlobalExercise();
      goal = await h.db.createGoal(ladderGoal(exerciseId), ownerId);
      firstStageId = goal.stages[0].id!;
      secondStageId = goal.stages[1].id!;
    });

    test('stamps one stage, leaving the rest of the ladder intact', () async {
      final at = DateTime.utc(2026, 12, 25, 9);
      final updated = await h.db.markStageAchieved(goal.id!, firstStageId, ownerId, at);

      final first = updated.stages.firstWhere((s) => s.id == firstStageId);
      final second = updated.stages.firstWhere((s) => s.id == secondStageId);
      expect(first.achievedAt?.toUtc(), at);
      expect(second.achievedAt, isNull);
    });

    test('is idempotent, overwriting the timestamp on re-send', () async {
      await h.db.markStageAchieved(goal.id!, firstStageId, ownerId, DateTime.utc(2026, 12, 25));
      final later = DateTime.utc(2026, 12, 31, 12);
      final updated = await h.db.markStageAchieved(goal.id!, firstStageId, ownerId, later);

      final first = updated.stages.firstWhere((s) => s.id == firstStageId);
      expect(first.achievedAt?.toUtc(), later);
    });

    test('throws NotFound for an unknown stage id', () async {
      await expectLater(
        h.db.markStageAchieved(goal.id!, 'no-such-stage', ownerId, DateTime.utc(2026)),
        throwsA(isA<NotFound>()),
      );
    });

    test('throws NotFound when another user targets the stage', () async {
      await expectLater(
        h.db.markStageAchieved(goal.id!, firstStageId, strangerId, DateTime.utc(2026)),
        throwsA(isA<NotFound>()),
      );
    });
  });
}

class _Harness extends DatabaseTestBase {}
