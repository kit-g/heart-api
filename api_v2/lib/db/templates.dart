part of 'db.dart';

mixin _Templates on _DatabaseBase implements ApiTemplateService {
  @override
  Future<Template> createTemplate({required String userId, required TemplateRequest body}) async {
    final rows = await _pool.execute(
      _saveTemplate.toSql(),
      parameters: body.toParams(),
    );
    return Template.fromRow(rows.first.toColumnMap());
  }

  @override
  Future<Template> updateTemplate({
    required String userId,
    required String templateId,
    required TemplateRequest body,
  }) async {
    final rows = await _pool.execute(
      _replaceTemplate.toSql(),
      parameters: {'templateId': templateId, ...body.toParams()},
    );
    if (rows.isEmpty) throw NotFound(type: 'Template', id: templateId);
    return Template.fromRow(rows.first.toColumnMap());
  }

  @override
  Future<TemplateListResponse> getTemplates({
    required String userId,
    String? cursor,
    int? pageSize = 30,
  }) async {
    final rows = await _pool.execute(
      _listTemplates.toSql(),
      parameters: {'userId': userId, 'cursor': cursor, 'limit': pageSize},
    );
    if (rows.isEmpty) return TemplateListResponse(templates: [], cursor: null);
    final templates = rows.map((row) => Template.fromRow(row.toColumnMap())).toList();
    return TemplateListResponse(templates: templates, cursor: templates.lastOrNull?.id);
  }

  @override
  Future<TemplateShareListResponse> getTemplateShares({
    required String userId,
    String? cursor,
    int? pageSize = 30,
  }) async {
    final rows = await _pool.execute(
      _listTemplateShares.toSql(),
      parameters: {'userId': userId, 'cursor': cursor, 'limit': pageSize},
    );
    if (rows.isEmpty) return TemplateShareListResponse(shares: [], cursor: null);
    final shares = rows.map((row) => TemplateShareItem.fromRow(row.toColumnMap())).toList();
    final nextCursor = rows.last.toColumnMap()['share_uuid']?.toString();
    return TemplateShareListResponse(shares: shares, cursor: nextCursor);
  }

  @override
  Future<TemplateShareItem> shareTemplate({
    required String coachId,
    required String targetUserId,
    required String masterTemplateId,
  }) async {
    final rows = await _pool.execute(
      _shareTemplate.toSql(),
      parameters: {'coachId': coachId, 'studentId': targetUserId, 'masterTemplateId': masterTemplateId},
    );
    if (rows.isEmpty) throw NotFound(type: 'Template', id: masterTemplateId);
    return TemplateShareItem.fromRow(rows.first.toColumnMap());
  }

  @override
  Future<void> deleteTemplate({required String coachId, required String templateId}) async {
    await _pool.execute(
      _deleteTemplate.toSql(),
      parameters: {'coachId': coachId, 'templateId': templateId},
    );
  }

  @override
  Future<void> deleteShare({required String coachId, required String shareId}) async {
    final parts = shareId.split('|');
    if (parts.length != 2) throw ArgumentError('Invalid share ID: $shareId');
    final rows = await _pool.execute(
      _deleteShare.toSql(),
      parameters: {'coachId': coachId, 'studentId': parts[0], 'masterTemplateId': parts[1]},
    );
    if (rows.isEmpty) throw NotFound(type: 'TemplateShare', id: shareId);
  }
}