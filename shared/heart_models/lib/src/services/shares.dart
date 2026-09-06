import '../models/pagination.dart';
import '../models/shares.dart';
import '../models/template.dart';

abstract interface class ApiTemplateService {
  /// `created` is true when this call minted the row; false when [body]'s
  /// [TemplateRequest.id] already named a template the caller owns — the
  /// upsync replay's idempotent-retry case (kit-g/heart-api#66) — in which
  /// case the existing row is returned untouched, content ignored. Templates
  /// carry no natural key, so an id is the only thing a retry can match on.
  Future<(Template, bool created)> createTemplate({required String userId, required TemplateRequest body});

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

  /// Ordered by the owner's arrangement — `(order, id)` ascending, which is
  /// [Template.compareTo]'s ordering — and paged on the same pair.
  ///
  /// Pass [folderId] to list one folder's contents, or [unfiledOnly] to list the
  /// templates in no folder at all. Neither lists everything the user owns.
  Future<Page<Template>> getTemplates({
    required String userId,
    OrderedCursor? cursor,
    int limit,
    String? folderId,
    bool unfiledOnly,
  });

  Future<Page<TemplateShare>> getTemplateShares({required String userId, String? cursor, int limit});

  Future<void> deleteTemplate({required String coachId, required String templateId});

  Future<void> deleteShare({required String coachId, required String shareId});
}
