import 'package:heart/globals/globals.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/models/errors.dart';
import 'package:heart/routes/goals.dart';
import 'package:heart_models/heart_models.dart';
import 'package:mockito/mockito.dart';
import 'package:relic_core/relic_core.dart';
import 'package:test/test.dart';

import '../helpers/request.dart';
import '../mocks.mocks.dart';

const _meId = 'u1';
const _otherId = 'u2';
const _goalId = '019def00-0000-7000-8000-000000000010';
const _stageId = '019def00-0000-7000-8000-000000000011';
const _exerciseId = '019def00-0000-7000-8000-000000000001';

void main() {
  late MockGoalService service;

  setUp(() {
    service = MockGoalService();
  });

  Request wire(Request req) {
    return req
      ..user = User(id: _meId)
      ..goalService = service;
  }

  Request createRequest(Map<String, dynamic> body) {
    return wire(jsonRequest(method: Method.post, path: '/goals', body: body));
  }

  group('createGoal', () {
    setUp(() {
      when(service.createGoal(any, any)).thenAnswer((i) async => i.positionalArguments[0] as Goal);
    });

    test('creates a frequency goal with no exercise scope', () async {
      final req = createRequest({
        'metric': 'workouts',
        'cadence': 'week',
        'stages': [
          {'target': 3},
        ],
      });

      final goal = await createGoal(req);

      expect(goal.metric, GoalMetric.workouts);
      expect(goal.cadence, GoalCadence.week);
      expect(goal.exerciseId, isNull);
      expect(goal.stages.single.target, 3);
      verify(service.createGoal(any, _meId)).called(1);
    });

    test('creates a staged strength ladder', () async {
      final req = createRequest({
        'metric': 'topSetWeight',
        'exerciseId': _exerciseId,
        'stages': [
          {'target': 100, 'dueOn': '2026-12-25'},
          {'target': 140, 'dueOn': '2027-12-25'},
        ],
      });

      final goal = await createGoal(req);

      expect(goal.metric, GoalMetric.topSetWeight);
      expect(goal.cadence, isNull);
      expect(goal.stages.map((s) => s.target), [100, 140]);
      expect(goal.stages.first.dueOn, DateTime.parse('2026-12-25'));
    });

    test('creates a monthly volume goal scoped to an exercise', () async {
      final req = createRequest({
        'metric': 'totalVolume',
        'exerciseId': _exerciseId,
        'cadence': 'month',
        'stages': [
          {'target': 20000},
        ],
      });

      final goal = await createGoal(req);

      expect(goal.metric, GoalMetric.totalVolume);
      expect(goal.cadence, GoalCadence.month);
    });

    test('rejects the frequency metric carrying an exercise', () async {
      final req = createRequest({
        'metric': 'workouts',
        'exerciseId': _exerciseId,
        'stages': [
          {'target': 3},
        ],
      });

      await expectLater(() => createGoal(req), throwsA(isA<BadRequest>()));
      verifyNever(service.createGoal(any, any));
    });

    test('rejects a per-exercise metric with no exercise', () async {
      final req = createRequest({
        'metric': 'topSetWeight',
        'stages': [
          {'target': 100},
        ],
      });

      await expectLater(() => createGoal(req), throwsA(isA<BadRequest>()));
    });

    test('rejects a recurring goal with a ladder', () async {
      final req = createRequest({
        'metric': 'workouts',
        'cadence': 'week',
        'stages': [
          {'target': 3},
          {'target': 4},
        ],
      });

      await expectLater(() => createGoal(req), throwsA(isA<BadRequest>()));
    });

    test('accepts a ladder whose later milestone is weaker', () async {
      // A deload ladder — strong by spring, ease off through a lighter block — is a
      // real plan, not a client bug, so the server no longer insists targets climb.
      final req = createRequest({
        'metric': 'topSetWeight',
        'exerciseId': _exerciseId,
        'stages': [
          {'target': 140, 'dueOn': '2026-04-01'},
          {'target': 100, 'dueOn': '2026-09-01'},
        ],
      });

      final goal = await createGoal(req);
      expect(goal.stages.map((s) => s.target), [140, 100]);
    });

    test('rejects a non-positive target', () async {
      final req = createRequest({
        'metric': 'workouts',
        'cadence': 'week',
        'stages': [
          {'target': 0},
        ],
      });

      await expectLater(() => createGoal(req), throwsA(isA<BadRequest>()));
    });

    test('rejects empty stages', () async {
      final req = createRequest({'metric': 'workouts', 'cadence': 'week', 'stages': []});

      await expectLater(() => createGoal(req), throwsA(isA<BadRequest>()));
    });

    test('rejects an unknown metric', () async {
      final req = createRequest({
        'metric': 'bodyWeight',
        'stages': [
          {'target': 80},
        ],
      });

      await expectLater(() => createGoal(req), throwsA(isA<BadRequest>()));
    });
  });

  group('getTargetUserGoals', () {
    test("returns a target user's goals when the requester may see them", () async {
      when(service.getTargetUserGoals(requesterId: _meId, targetUserId: _otherId)).thenAnswer(
        (_) async => [
          Goal(
            id: _goalId,
            metric: GoalMetric.workouts,
            cadence: GoalCadence.week,
            stages: [GoalStage(id: _stageId, target: 3)],
          ),
        ],
      );

      final req = wire(bareRequest(method: Method.get, path: '/accounts/$_otherId/goals'));
      final response = await getTargetUserGoalsById(req, _otherId);

      expect(response.goals.single.id, _goalId);
      expect(response.toMap()['goals'], hasLength(1));
      verify(service.getTargetUserGoals(requesterId: _meId, targetUserId: _otherId)).called(1);
    });

    test('propagates Forbidden when the requester is not a connection', () async {
      when(
        service.getTargetUserGoals(requesterId: _meId, targetUserId: _otherId),
      ).thenThrow(const Forbidden(reason: 'not connected'));

      final req = wire(bareRequest(method: Method.get, path: '/accounts/$_otherId/goals'));

      await expectLater(() => getTargetUserGoalsById(req, _otherId), throwsA(isA<Forbidden>()));
    });
  });

  group('markStageAchieved', () {
    test('stamps the stage the app reports as met', () async {
      final achieved = DateTime.utc(2026, 12, 20, 9, 30);
      when(service.markStageAchieved(any, any, any, any)).thenAnswer(
        (i) async => Goal(
          id: _goalId,
          metric: GoalMetric.topSetWeight,
          exerciseId: _exerciseId,
          stages: [GoalStage(id: _stageId, target: 100, achievedAt: i.positionalArguments[3] as DateTime)],
        ),
      );

      final req = wire(
        jsonRequest(
          method: Method.put,
          path: '/goals/$_goalId/stages/$_stageId',
          body: {'achievedAt': achieved.toIso8601String()},
        ),
      );

      final goal = await markStageAchievedById(req, _goalId, _stageId);

      expect(goal.stages.single.isAchieved, isTrue);
      expect(goal.isComplete, isTrue);
      verify(service.markStageAchieved(_goalId, _stageId, _meId, achieved)).called(1);
    });

    test('requires achievedAt', () async {
      final req = wire(
        jsonRequest(
          method: Method.put,
          path: '/goals/$_goalId/stages/$_stageId',
          body: {},
        ),
      );

      await expectLater(() => markStageAchievedById(req, _goalId, _stageId), throwsA(isA<BadRequest>()));
    });

    test('surfaces an unknown stage as a 404', () async {
      when(
        service.markStageAchieved(any, any, any, any),
      ).thenThrow(const NotFound(type: 'Goal stage', id: _stageId));

      final req = wire(
        jsonRequest(
          method: Method.put,
          path: '/goals/$_goalId/stages/$_stageId',
          body: {'achievedAt': DateTime.utc(2026, 12, 20).toIso8601String()},
        ),
      );

      await expectLater(() => markStageAchievedById(req, _goalId, _stageId), throwsA(isA<NotFound>()));
    });
  });

  group('deleteGoal', () {
    test('deletes and returns no content', () async {
      when(service.deleteGoal(any, any)).thenAnswer((_) async {});

      final req = wire(bareRequest(method: Method.delete, path: '/goals/$_goalId'));

      await expectLater(() => deleteGoalById(req, _goalId), throwsA(isA<NoContent>()));
      verify(service.deleteGoal(_goalId, _meId)).called(1);
    });
  });

  group('updateGoal', () {
    test('replaces the ladder, preserving stage ids the client sends back', () async {
      when(service.updateGoal(any, any, any)).thenAnswer((i) async => i.positionalArguments[1] as Goal);

      final req = wire(
        jsonRequest(
          method: Method.put,
          path: '/goals/$_goalId',
          body: {
            'metric': 'topSetWeight',
            'exerciseId': _exerciseId,
            'stages': [
              {'id': _stageId, 'target': 100},
              {'target': 140},
            ],
          },
        ),
      );

      final goal = await updateGoalById(req, _goalId);

      expect(goal.stages.first.id, _stageId);
      expect(goal.stages.last.id, isNull, reason: 'a new rung gets its id minted in the db layer');
      verify(service.updateGoal(_goalId, any, _meId)).called(1);
    });

    test('preserves achievedAt through a full replace', () async {
      // The bug: a full-replace edit round-trips the ladder, and if the input layer
      // drops achievedAt the server blanks every stamped rung. Editing must not
      // destroy an achievement (decision 2 — stable across devices/reinstalls).
      when(service.updateGoal(any, any, any)).thenAnswer((i) async => i.positionalArguments[1] as Goal);

      final achieved = DateTime.utc(2026, 12, 25, 9);
      final req = wire(
        jsonRequest(
          method: Method.put,
          path: '/goals/$_goalId',
          body: {
            'metric': 'topSetWeight',
            'exerciseId': _exerciseId,
            'stages': [
              {'id': _stageId, 'target': 100, 'achievedAt': achieved.toIso8601String()},
              {'target': 140},
            ],
          },
        ),
      );

      final goal = await updateGoalById(req, _goalId);

      expect(goal.stages.first.achievedAt?.toUtc(), achieved);
      expect(goal.stages.first.isAchieved, isTrue);
      expect(goal.stages.last.achievedAt, isNull, reason: 'the unstamped rung stays unstamped');
    });
  });
}
