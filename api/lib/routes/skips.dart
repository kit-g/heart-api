import 'package:heart/core/handler.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/inputs/inputs.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/models/errors.dart';
import 'package:heart/models/pagination.dart';
import 'package:heart_models/heart_models.dart';
import 'package:relic/relic.dart';

Future<Paginated<TrainingSkip>> getMySkips(Request req) async {
  final query = PageQuery.fromRequest(req);
  final page = await req.skipService.getSkips(userId: req.userId, cursor: query.cursor, limit: query.limit);
  return Paginated<TrainingSkip>.from(page, itemsKey: 'skips', cursorOf: (skip) => skip.id!);
}

Future<Model> createSkip(Request req) async {
  final input = await SkipIn.fromRequest(req);
  final (skip, isNew) = await req.skipService.createSkip(userId: req.userId, skip: input.skip);
  if (isNew) return Created(skip);
  return skip;
}

Future<Model> deleteSkip(Request req) {
  return deleteSkipById(req, req.rawPathParameters[#skipId]!);
}

Future<Model> deleteSkipById(Request req, String skipId) async {
  await req.skipService.deleteSkip(userId: req.userId, skipId: skipId);
  throw const NoContent();
}
