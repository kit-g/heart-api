import '../models/pagination.dart';
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

  /// Pass [folderId] to list one folder's contents, or [unfiledOnly] to list the
  /// templates in no folder at all. Neither lists everything the user owns.
  Future<Page<Template>> getTemplates({
    required String userId,
    String? cursor,
    int limit,
    String? folderId,
    bool unfiledOnly,
  });

  Future<Page<TemplateShare>> getTemplateShares({required String userId, String? cursor, int limit});

  Future<void> deleteTemplate({required String coachId, required String templateId});

  Future<void> deleteShare({required String coachId, required String shareId});
}
