part of 'db.dart';

mixin _Threads on _DatabaseBase implements ThreadService, CoachNoteService, ReportService {
  @override
  Future<Thread?> openThread({required String userId, required String connectionId}) async {
    final rows = await _pool.execute(
      _openThread.toSql(),
      parameters: {'userId': userId, 'connectionId': connectionId},
    );
    return switch (rows.firstOrNull?.toColumnMap()) {
      null => null,
      final row => Thread.fromRow(row),
    };
  }

  @override
  Future<ThreadParties?> getThreadParties({required String senderId, required String threadId}) async {
    final rows = await _pool.execute(
      _threadParties.toSql(),
      parameters: {'senderId': senderId, 'threadId': threadId},
    );
    return switch (rows.firstOrNull?.toColumnMap()) {
      {'recipient_id': final String recipientId} => (
        threadId: threadId,
        senderId: senderId,
        recipientId: recipientId,
      ),
      _ => null,
    };
  }

  @override
  Future<(ThreadItem, bool created)> addThreadItem({
    required String senderId,
    required String threadId,
    required String id,
    required String kind,
    required String content,
    required String commitment,
    required String tag,
    required String tagKey,
    required DateTime at,
    required DateTime createdAt,
    String? subjectType,
    String? subjectId,
  }) async {
    final rows = await _pool.execute(
      _addThreadItem.toSql(),
      parameters: {
        'senderId': senderId,
        'threadId': threadId,
        'id': id,
        'kind': kind,
        'content': content,
        'commitment': commitment,
        'tag': tag,
        'tagKey': tagKey,
        'at': at.toUtc(),
        'createdAt': createdAt.toUtc(),
        'subjectType': subjectType,
        'subjectId': subjectId,
      },
    );
    if (rows.isEmpty) throw const Forbidden(code: 'id_taken', reason: 'this id belongs to something else');
    final row = rows.first.toColumnMap();
    return (
      ThreadItem.fromRow(
        row,
        cursor: ChangeCursor(xid: row['xid'] as String, id: row['id'].toString()).toString(),
      ),
      row['created'] as bool,
    );
  }

  @override
  Future<List<Thread>> getThreads({required String userId}) async {
    final rows = await _pool.execute(_listThreads.toSql(), parameters: {'userId': userId});
    return rows.map((row) => Thread.fromRow(row.toColumnMap())).toList();
  }

  @override
  Future<Page<ThreadItem>> getThreadItems({
    required String userId,
    required String threadId,
    String? since,
    String? before,
    String? subjectType,
    String? subjectId,
    int limit = 50,
  }) async {
    final after = since == null ? null : ChangeCursor.parse(since);
    final until = before == null ? null : ChangeCursor.parse(before);
    final rows = await _pool.execute(
      (after == null ? _listThreadItemsBackward : _listThreadItemsForward).toSql(),
      parameters: {
        'userId': userId,
        'threadId': threadId,
        'xid': after?.xid ?? until?.xid,
        'itemId': after?.id ?? until?.id,
        'subjectType': subjectType,
        'subjectId': subjectId,
        'limit': limit + 1,
      },
    );
    final maps = rows.map((row) => row.toColumnMap()).toList();
    if (maps.firstOrNull?['forbidden'] == true) {
      throw const Forbidden(reason: 'You do not have permission to read this thread.');
    }
    final items = [
      for (final row in maps)
        ThreadItem.fromRow(
          row,
          cursor: ChangeCursor(xid: row['xid'] as String, id: row['id'].toString()).toString(),
        ),
    ];
    final hasMore = items.length > limit;
    return Page(items: hasMore ? items.sublist(0, limit) : items, hasMore: hasMore);
  }

  @override
  Future<void> markThreadRead({required String userId, required String threadId, required String cursor}) async {
    final position = ChangeCursor.parse(cursor);
    await _pool.execute(
      _markThreadRead.toSql(),
      parameters: {'userId': userId, 'threadId': threadId, 'xid': position.xid, 'itemId': position.id},
    );
  }

  @override
  Future<String?> clearThread({required String userId, required String threadId}) async {
    final rows = await _pool.execute(_clearThread.toSql(), parameters: {'userId': userId, 'threadId': threadId});
    return rows.firstOrNull?.toColumnMap()['other_id'] as String?;
  }

  @override
  Future<CoachNote> saveNote({
    required String coachId,
    required String id,
    required String connectionId,
    required String content,
  }) async {
    final rows = await _pool.execute(
      _saveNote.toSql(),
      parameters: {'coachId': coachId, 'id': id, 'connectionId': connectionId, 'content': content},
    );
    if (rows.isEmpty) throw NotFound(type: 'Connection', id: connectionId);
    return CoachNote.fromRow(rows.first.toColumnMap());
  }

  @override
  Future<Page<CoachNote>> getNotes({
    required String coachId,
    String? connectionId,
    String? cursor,
    int limit = 50,
  }) async {
    final rows = await _pool.execute(
      _listNotes.toSql(),
      parameters: {'coachId': coachId, 'connectionId': connectionId, 'cursor': cursor, 'limit': limit + 1},
    );
    final notes = rows.map((row) => CoachNote.fromRow(row.toColumnMap())).toList();
    final hasMore = notes.length > limit;
    return Page(items: hasMore ? notes.sublist(0, limit) : notes, hasMore: hasMore);
  }

  @override
  Future<void> deleteNote({required String coachId, required String id}) async {
    await _pool.execute(_deleteNote.toSql(), parameters: {'coachId': coachId, 'id': id});
  }

  @override
  Future<void> fileReport({
    required String reporterId,
    required String reportedId,
    String? connectionId,
    required String reason,
    required String sealed,
    required bool verified,
  }) async {
    await _pool.execute(
      _fileReport.toSql(),
      parameters: {
        'reporterId': reporterId,
        'reportedId': reportedId,
        'connectionId': connectionId,
        'reason': reason,
        'sealed': sealed,
        'verified': verified,
      },
    );
  }
}
