import 'package:heart/core/request.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/inputs/inputs.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/models/errors.dart';
import 'package:heart/models/pagination.dart';
import 'package:heart_models/heart_models.dart';
import 'package:relic/relic.dart';

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

Future<Paginated<Template>> getMyTemplates(final Request request) async {
  final query = PageQuery.fromRequest(request);
  final page = await request.templatesService.getTemplates(
    userId: request.userId,
    limit: query.limit,
    cursor: query.cursor,
  );
  return Paginated<Template>.from(page, itemsKey: 'templates', cursorOf: (t) => t.id);
}

Future<Paginated<TemplateShare>> getMyTemplateShares(final Request request) async {
  final query = PageQuery.fromRequest(request);
  final page = await request.templatesService.getTemplateShares(
    userId: request.userId,
    limit: query.limit,
    cursor: query.cursor,
  );
  // The share cursor is supplied explicitly by the service (Page.cursor); it
  // isn't a field on TemplateShare, so no cursorOf here.
  return Paginated<TemplateShare>.from(page, itemsKey: 'shares');
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
