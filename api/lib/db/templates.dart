part of 'db.dart';

mixin _Templates on _DatabaseBase implements IdempotentTemplateService {
  @override
  Future<Template> createTemplate({required String userId, required TemplateRequest body}) async =>
      (await createTemplateOrExisting(userId: userId, body: body)).$1;

  @override
  Future<(Template, bool created)> createTemplateOrExisting({
    required String userId,
    required TemplateRequest body,
  }) async {
    try {
      final rows = await _retryOnCreateRace(
        () => _pool.execute(
          _saveTemplate.toSql(),
          parameters: {'id': body.id, ...body.toParams()},
        ),
      );
      // Empty means `folderId` names a folder the user does not own — the id
      // pre-check (kit-g/heart-api#66) has already ruled out "this id is
      // mine", so an empty result can only be the folder guard failing.
      if (rows.isEmpty) throw NotFound(type: 'TemplateFolder', id: body.folderId ?? '');
      final row = rows.first.toColumnMap();
      return (Template.fromRow(row), row['created'] as bool);
    } on ServerException catch (e) {
      _rethrowForeignId(e);
    }
  }

  @override
  Future<Template> updateTemplate({
    required String userId,
    required String templateId,
    required TemplateRequest body,
  }) async {
    try {
      final rows = await _pool.execute(
        _replaceTemplate.toSql(),
        parameters: {'templateId': templateId, 'movesFolder': body.movesFolder, ...body.toParams()},
      );
      if (rows.isEmpty) throw NotFound(type: 'Template', id: templateId);
      return Template.fromRow(rows.first.toColumnMap());
    } on ServerException catch (e) {
      _rethrowCapped(e);
    }
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
    OrderedCursor? cursor,
    int limit = 30,
    String? folderId,
    bool unfiledOnly = false,
  }) async {
    // Fetch one extra row so hasMore is authoritative without a second query.
    final rows = await _pool.execute(
      _listTemplates.toSql(),
      parameters: {
        'userId': userId,
        'cursorOrder': cursor?.order,
        'cursorId': cursor?.id,
        'limit': limit + 1,
        'folderId': folderId,
        'unfiledOnly': unfiledOnly,
      },
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
    final shares = await _shareMasters(
      coachId: coachId,
      targetUserId: targetUserId,
      masterTemplateIds: [masterTemplateId],
    );
    if (shares.isEmpty) throw NotFound(type: 'Template', id: masterTemplateId);
    return shares.first;
  }

  /// The shared body of both assignment endpoints. Pass [masterTemplateIds] to
  /// assign specific templates or [folderId] to assign everything in a folder;
  /// the statement resolves whichever is supplied.
  ///
  /// Returns empty when nothing matched — an unknown student, an unknown or
  /// empty folder, or template ids that are not the coach's. Callers decide
  /// which of those it was, because only they know what was asked for.
  Future<List<TemplateShare>> _shareMasters({
    required String coachId,
    required String targetUserId,
    List<String> masterTemplateIds = const [],
    String? folderId,
  }) async {
    final rows = await _pool.execute(
      _shareTemplates.toSql(),
      parameters: {
        'coachId': coachId,
        'studentId': targetUserId,
        'masterTemplateIds': masterTemplateIds,
        'folderId': folderId,
      },
    );
    if (rows.isEmpty) return const [];

    final maps = rows.map((row) => row.toColumnMap()).toList();
    // The gate is per (coach, student), so every row carries the same verdict.
    if (maps.first['forbidden'] == true) {
      throw const Forbidden(reason: 'You do not have permission to assign templates to this user.');
    }
    return maps.map(TemplateShare.fromRow).toList();
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
