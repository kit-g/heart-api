import 'package:heart/globals/globals.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/models/errors.dart';
import 'package:heart/models/templates.dart';
import 'package:heart/routes/permissions.dart';
import 'package:relic/relic.dart';

const _limitParam = IntQueryParam('pageSize');

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

Future<TemplateItem> assignTemplateToUser(final Request request) async {
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

  return templatesDb.shareTemplate(
    coachId: request.userId,
    studentId: targetUserId,
    masterTemplateId: templateId,
  );
}
