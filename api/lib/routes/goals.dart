import 'package:heart/globals/globals.dart';
import 'package:heart/inputs/inputs.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/models/goals.dart';
import 'package:heart_models/heart_models.dart';
import 'package:relic/relic.dart';

import '../models/errors.dart';

Future<GoalsResponse> getGoals(final Request req) async {
  final goals = await req.goalService.getGoals(req.userId);
  return GoalsResponse(goals: goals);
}

Future<Goal> createGoal(final Request req) async {
  final input = await GoalCreateIn.fromRequest(req);
  return req.goalService.createGoal(input.goal, req.userId);
}

Future<Goal> updateGoal(final Request req) {
  return updateGoalById(req, req.rawPathParameters[#goalId]!);
}

Future<Goal> updateGoalById(final Request req, final String goalId) async {
  final input = await GoalUpdateIn.fromRequest(req);
  return req.goalService.updateGoal(goalId, input.goal, req.userId);
}

Future<Model> deleteGoal(final Request req) {
  return deleteGoalById(req, req.rawPathParameters[#goalId]!);
}

Future<Model> deleteGoalById(final Request req, final String goalId) async {
  await req.goalService.deleteGoal(goalId, req.userId);
  throw const NoContent();
}

Future<Goal> markStageAchieved(final Request req) {
  return markStageAchievedById(
    req,
    req.rawPathParameters[#goalId]!,
    req.rawPathParameters[#stageId]!,
  );
}

Future<Goal> markStageAchievedById(final Request req, final String goalId, final String stageId) async {
  final input = await StageAchievedIn.fromRequest(req);
  return req.goalService.markStageAchieved(goalId, stageId, req.userId, input.achievedAt);
}
