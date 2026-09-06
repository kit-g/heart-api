import 'package:heart/core/handler.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/inputs/inputs.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/models/errors.dart';
import 'package:heart/models/pagination.dart';
import 'package:heart_models/heart_models.dart';
import 'package:relic/relic.dart';

Future<Model> createTemplate(Request request) async {
  final input = await TemplateCreateIn.fromRequest(request);
  final (template, isNew) = await request.templatesService.createTemplateOrExisting(
    userId: request.userId,
    body: input.request,
  );
  if (isNew) return Created(template);
  return template;
}

Future<Template> updateTemplate(Request request) {
  return updateTemplateById(request, request.rawPathParameters[#templateId]!);
}

Future<Template> updateTemplateById(Request request, String templateId) async {
  final input = await TemplateUpdateIn.fromRequest(request);
  return request.templatesService.updateTemplate(
    userId: request.userId,
    templateId: templateId,
    body: input.request,
  );
}

Future<Template> getMyTemplate(Request request) async {
  return request.templatesService.getTemplate(
    userId: request.userId,
    templateId: request.pathParameters.raw[#templateId]!,
  );
}

Future<Paginated<Template>> getMyTemplates(Request request) async {
  final query = TemplateListQuery.fromRequest(request);
  final page = await request.templatesService.getTemplates(
    userId: request.userId,
    limit: query.limit,
    cursor: query.cursor,
    folderId: query.folderId,
    unfiledOnly: query.unfiledOnly,
  );
  // The listing walks (order, id), so the cursor has to carry both.
  return Paginated<Template>.from(
    page,
    itemsKey: 'templates',
    cursorOf: (t) => OrderedCursor(order: t.order, id: t.id).toString(),
  );
}

Future<Paginated<TemplateShare>> getMyTemplateShares(Request request) async {
  final query = PageQuery.fromRequest(request);
  final page = await request.templatesService.getTemplateShares(
    userId: request.userId,
    limit: query.limit,
    cursor: query.cursor,
  );
  return Paginated<TemplateShare>.from(page, itemsKey: 'shares', cursorOf: (s) => s.id);
}

Future<TemplateShare> assignTemplateToUser(Request request) async {
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

Future<NoContent> deleteMyTemplate(Request request) async {
  await request.templatesService.deleteTemplate(
    coachId: request.userId,
    templateId: request.pathParameters.raw[#templateId]!,
  );
  throw const NoContent();
}

Future<NoContent> deleteMyTemplateShare(Request request) async {
  await request.templatesService.deleteShare(
    coachId: request.userId,
    shareId: request.pathParameters.raw[#shareId]!,
  );
  throw const NoContent();
}
