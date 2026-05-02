import 'package:heart/core/request.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/models/errors.dart';
import 'package:heart/models/templates.dart';
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

Future<Template> getMyTemplate(final Request request) async {
  return request.templatesService.getTemplate(
    userId: request.userId,
    templateId: request.pathParameters.raw[#templateId]!,
  );
}

Future<TemplateResponse> getMyTemplates(final Request request) async {
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

Future<TemplateShare> assignTemplateToUser(final Request request) async {
  final userId = request.userId;
  final targetUserId = request.pathParameters.raw[#targetUserId]!;
  final templateId = request.pathParameters.raw[#templateId]!;

  if (userId == targetUserId) {
    throw const Forbidden(reason: 'You cannot assign templates to yourself.');
  }

  return await request.templatesService.shareTemplate(
    coachId: userId,
    targetUserId: targetUserId,
    masterTemplateId: templateId,
  );
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
