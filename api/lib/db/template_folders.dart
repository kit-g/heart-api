part of 'db.dart';

mixin _TemplateFolders on _DatabaseBase, _Templates implements IdempotentTemplateFolderService {
  @override
  Future<Iterable<TemplateFolder>> getFolders({required String userId}) async {
    final rows = await _pool.execute(
      _listTemplateFolders.toSql(),
      parameters: {'userId': userId},
    );
    return rows.map((row) => TemplateFolder.fromRow(row.toColumnMap()));
  }

  @override
  Future<TemplateFolder> createFolder({required String userId, required TemplateFolder folder}) async =>
      (await createFolderOrExisting(userId: userId, folder: folder)).$1;

  @override
  Future<(TemplateFolder, bool created)> createFolderOrExisting({
    required String userId,
    required TemplateFolder folder,
  }) async {
    try {
      final rows = await _retryOnCreateRace(
        () => _pool.execute(
          _createTemplateFolder.toSql(),
          parameters: {'userId': userId, 'id': folder.id, 'name': folder.name, 'orderIndex': folder.order},
        ),
      );
      final row = rows.first.toColumnMap();
      return (TemplateFolder.fromRow(row), row['created'] as bool);
    } on ServerException catch (e) {
      _rethrowForeignId(e);
    }
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
