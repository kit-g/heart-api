import 'package:heart/globals/globals.dart';
import 'package:heart/inputs/inputs.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/models/goals.dart';
import 'package:heart_models/heart_models.dart';
import 'package:relic/relic.dart';

import '../models/errors.dart';

Future<GoalsResponse> getTargetUserGoals(Request req) => getTargetUserGoalsById(
  req,
  req.rawPathParameters[#targetUserId]!,
  archived: req.queryParameters.raw['archived'] == 'true',
);

Future<GoalsResponse> getTargetUserGoalsById(
  Request req,
  String targetUserId, {
  bool archived = false,
}) async {
  final goals = await req.goalService.getTargetUserGoals(
    requesterId: req.userId,
    targetUserId: targetUserId,
    archived: archived,
  );
  return GoalsResponse(goals: goals);
}

Future<Goal> createGoal(Request req) async {
  final input = await GoalCreateIn.fromRequest(req);
  return req.goalService.createGoal(input.goal, req.userId);
}

Future<Goal> updateGoal(Request req) {
  return updateGoalById(req, req.rawPathParameters[#goalId]!);
}

Future<Goal> updateGoalById(Request req, String goalId) async {
  final input = await GoalUpdateIn.fromRequest(req);
  return req.goalService.updateGoal(goalId, input.goal, req.userId);
}

Future<Model> deleteGoal(Request req) {
  return deleteGoalById(req, req.rawPathParameters[#goalId]!);
}

Future<Model> deleteGoalById(Request req, String goalId) async {
  await req.goalService.deleteGoal(goalId, req.userId);
  throw const NoContent();
}

Future<Goal> markStageAchieved(Request req) {
  return markStageAchievedById(
    req,
    req.rawPathParameters[#goalId]!,
    req.rawPathParameters[#stageId]!,
  );
}

Future<Goal> markStageAchievedById(Request req, String goalId, String stageId) async {
  final input = await StageAchievedIn.fromRequest(req);
  return req.goalService.markStageAchieved(
    goalId,
    stageId,
    req.userId,
    input.achievedAt,
    achievedBy: input.achievedBy,
  );
}
