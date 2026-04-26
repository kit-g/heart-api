import 'package:heart/core/request.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/models/errors.dart';
import 'package:heart/models/templates.dart';
import 'package:heart/routes/permissions.dart';
import 'package:heart_models/heart_models.dart';
import 'package:relic/relic.dart';

const _limitParam = IntQueryParam('pageSize');

Future<Template> createTemplate(final Request request) async {
  final body = await request.json();
  return request.templatesService.createTemplate(
    userId: request.userId,
    body: TemplateRequest(userId: request.userId, body: body),
  );
}

Future<Template> updateTemplate(final Request request) async {
  final templateId = request.pathParameters.raw[#templateId]!;
  final body = await request.json();
  return request.templatesService.updateTemplate(
    userId: request.userId,
    templateId: templateId,
    body: TemplateRequest(userId: request.userId, body: body),
  );
}

Future<TemplateListResponse> getMyTemplates(final Request request) async {
  return request.templatesService.getTemplates(
    userId: request.userId,
    pageSize: request.queryParameters(_limitParam),
    cursor: request.queryParameters.raw['cursor'],
  );
}

Future<TemplateShareListResponse> getMyTemplateShares(final Request request) async {
  return request.templatesService.getTemplateShares(
    userId: request.userId,
    pageSize: request.queryParameters(_limitParam),
    cursor: request.queryParameters.raw['cursor'],
  );
}

Future<TemplateShareItem> assignTemplateToUser(final Request request) async {
  final templatesDb = request.templatesService;
  final connectionsDb = request.connectionsService;
  final userId = request.userId;
  final targetUserId = request.pathParameters.raw[#targetUserId]!;
  final templateId = request.pathParameters.raw[#templateId]!;

  if (userId == targetUserId) {
    throw const Forbidden(reason: 'You cannot assign templates to yourself.');
  }

  final allowed = await allowedByConnection(db: connectionsDb, userId: request.userId, targetUserId: targetUserId);

  if (!allowed) {
    throw const Forbidden(reason: 'You do not have permission to assign templates to this user.');
  }

  try {
    return await templatesDb.shareTemplate(
      coachId: request.userId,
      targetUserId: targetUserId,
      masterTemplateId: templateId,
    );
  } on StateError catch (e) {
    throw BadRequest(
      reason: e.message,
      payload: request.signature(),
    );
  }
}

Future<NoContent> deleteMyTemplate(final Request request) async {
  await request.templatesService.deleteTemplate(
    coachId: request.userId,
    templateId: request.pathParameters.raw[#templateId]!,
  );
  throw const NoContent();
}

Future<NoContent> deleteMyTemplateShare(final Request request) async {
  try {
    await request.templatesService.deleteShare(
      coachId: request.userId,
      shareId: request.pathParameters.raw[#shareId]!,
    );
  } on ArgumentError catch (e) {
    throw BadRequest(reason: e.message.toString());
  }
  throw const NoContent();
}
