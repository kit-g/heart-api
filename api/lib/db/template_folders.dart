part of 'db.dart';

mixin _TemplateFolders on _DatabaseBase, _Templates implements ApiTemplateFolderService {
  @override
  Future<Iterable<TemplateFolder>> getFolders({required String userId}) async {
    final rows = await _pool.execute(
      _listTemplateFolders.toSql(),
      parameters: {'userId': userId},
    );
    return rows.map((row) => TemplateFolder.fromRow(row.toColumnMap()));
  }

  @override
  Future<TemplateFolder> createFolder({required String userId, required TemplateFolder folder}) async {
    final rows = await _pool.execute(
      _createTemplateFolder.toSql(),
      parameters: {'userId': userId, 'name': folder.name, 'orderIndex': folder.order},
    );
    // ON CONFLICT DO NOTHING: no row means the name is already in use.
    if (rows.isEmpty) throw BadRequest(reason: 'you already have a folder called "${folder.name}"');
    return TemplateFolder.fromRow(rows.first.toColumnMap());
  }

  @override
  Future<TemplateFolder> updateFolder({
    required String userId,
    required String folderId,
    required TemplateFolder folder,
  }) async {
    final rows = await _pool.execute(
      _updateTemplateFolder.toSql(),
      parameters: {
        'userId': userId,
        'folderId': folderId,
        'name': folder.name,
        'orderIndex': folder.order,
      },
    );
    if (rows.isEmpty) throw NotFound(type: 'TemplateFolder', id: folderId);

    final row = rows.first.toColumnMap();
    if (row['name_taken'] == true) {
      throw BadRequest(reason: 'you already have a folder called "${folder.name}"');
    }
    return TemplateFolder.fromRow(row);
  }

  @override
  Future<void> deleteFolder({required String userId, required String folderId}) async {
    final rows = await _pool.execute(
      _deleteTemplateFolder.toSql(),
      parameters: {'userId': userId, 'folderId': folderId},
    );
    if (rows.isEmpty) throw NotFound(type: 'TemplateFolder', id: folderId);
  }

  @override
  Future<Iterable<TemplateShare>> shareFolder({
    required String coachId,
    required String targetUserId,
    required String folderId,
  }) async {
    final shares = await _shareMasters(
      coachId: coachId,
      targetUserId: targetUserId,
      folderId: folderId,
    );
    if (shares.isNotEmpty) return shares;

    // Nothing was shared, which the statement cannot explain on its own: an
    // empty folder is a legitimate no-op, an unknown folder or student is a 404.
    // Worth a second query only on this rare path.
    final rows = await _pool.execute(
      _diagnoseEmptyFolderShare.toSql(),
      parameters: {'coachId': coachId, 'studentId': targetUserId, 'folderId': folderId},
    );
    final diagnosis = rows.first.toColumnMap();
    if (diagnosis['folder_exists'] != true) throw NotFound(type: 'TemplateFolder', id: folderId);
    if (diagnosis['student_exists'] != true) throw NotFound(type: 'User', id: targetUserId);
    return const [];
  }
}
