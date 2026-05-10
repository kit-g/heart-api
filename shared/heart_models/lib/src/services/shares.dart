import '../models/shares.dart';
import '../models/template.dart';

abstract interface class ApiTemplateService {
  Future<Template> createTemplate({required String userId, required TemplateRequest body});

  Future<Template> updateTemplate({
    required String userId,
    required String templateId,
    required TemplateRequest body,
  });

  Future<TemplateShare> shareTemplate({
    required String coachId,
    required String targetUserId,
    required String masterTemplateId,
  });

  Future<Template> getTemplate({required String userId, required String templateId});

  Future<TemplateResponse> getTemplates({required String userId, String? cursor, int? pageSize});

  Future<TemplateShareListResponse> getTemplateShares({required String userId, String? cursor, int? pageSize});

  Future<void> deleteTemplate({required String coachId, required String templateId});

  Future<void> deleteShare({required String coachId, required String shareId});
}
