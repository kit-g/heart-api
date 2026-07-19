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
  Future<Template> getTemplate({required String userId, required String templateId}) async {
    final rows = await _pool.execute(
      _getTemplate.toSql(),
      parameters: {'userId': userId, 'templateId': templateId},
    );
    if (rows.isEmpty) throw NotFound(type: 'Template', id: templateId);
    return Template.fromRow(rows.first.toColumnMap());
  }

  @override
  Future<Page<Template>> getTemplates({
    required String userId,
    String? cursor,
    int limit = 30,
  }) async {
    // Fetch one extra row so hasMore is authoritative without a second query.
    final rows = await _pool.execute(
      _listTemplates.toSql(),
      parameters: {'userId': userId, 'cursor': cursor, 'limit': limit + 1},
    );
    final templates = rows.map((row) => Template.fromRow(row.toColumnMap())).toList();
    final hasMore = templates.length > limit;
    return Page(items: hasMore ? templates.sublist(0, limit) : templates, hasMore: hasMore);
  }

  @override
  Future<Page<TemplateShare>> getTemplateShares({
    required String userId,
    String? cursor,
    int limit = 30,
  }) async {
    // Fetch one extra row so hasMore is authoritative without a second query.
    final rows = await _pool.execute(
      _listTemplateShares.toSql(),
      parameters: {'userId': userId, 'cursor': cursor, 'limit': limit + 1},
    );
    final shares = rows.map((row) => TemplateShare.fromRow(row.toColumnMap())).toList();
    final hasMore = shares.length > limit;
    return Page(items: hasMore ? shares.sublist(0, limit) : shares, hasMore: hasMore);
  }

  @override
  Future<TemplateShare> shareTemplate({
    required String coachId,
    required String targetUserId,
    required String masterTemplateId,
  }) async {
    final rows = await _pool.execute(
      _shareTemplate.toSql(),
      parameters: {'coachId': coachId, 'studentId': targetUserId, 'masterTemplateId': masterTemplateId},
    );
    if (rows.isEmpty) throw NotFound(type: 'Template', id: masterTemplateId);
    final row = rows.first.toColumnMap();
    if (row['forbidden'] == true) {
      throw const Forbidden(reason: 'You do not have permission to assign templates to this user.');
    }
    return TemplateShare.fromRow(row);
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
    final rows = await _pool.execute(
      _deleteShare.toSql(),
      parameters: {'coachId': coachId, 'shareId': shareId},
    );
    if (rows.isEmpty) throw NotFound(type: 'TemplateShare', id: shareId);
  }
}
