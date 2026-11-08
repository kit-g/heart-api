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
      {'recipient_id': final String recipientId, 'connection_id': final String connectionId} => (
        threadId: threadId,
        senderId: senderId,
        recipientId: recipientId,
        connectionId: connectionId,
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
    Future<List<Map<String, dynamic>>> attempt() async {
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
          'perMinute': _maxMessagesPerMinute,
        },
      );
      return [for (final row in rows) row.toColumnMap()];
    }

    // A retry racing the request it repeats waits for that one's insert, and then
    // can't see the row, which committed after its snapshot: once more sees it.
    var rows = await attempt();
    if (rows.single['created'] == null) rows = await attempt();

    // No cursor: this item's place may be past a transaction still writing, and a
    // read position or a page taken from it would skip what that one writes.
    return switch (rows.single) {
      {'created': final bool created} && final row => (ThreadItem.fromRow(row), created),
      {'open': false} => throw const Forbidden(
        code: 'thread_closed',
        reason: 'This thread takes no new messages from you.',
      ),
      {'sent': final int sent} when sent >= _maxMessagesPerMinute => throw const TooManyRequests(
        reason: 'at most $_maxMessagesPerMinute messages a minute',
        retryAfter: 60,
      ),
      _ => throw _idTaken,
    };
  }

  /// A guard for the beta, not a promise: nobody is expected to reach it.
  static const _maxMessagesPerMinute = 60;

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
    switch (maps.firstOrNull) {
      case {'forbidden': true}:
        throw _notYourThread;
      case {'stale': true}:
        throw _staleCursor;
    }
    final items = [
      for (final row in maps)
        ThreadItem.fromRow(
          row,
          cursor: ChangeCursor(xid: row['xid_text'] as String, id: row['id'].toString()).toString(),
        ),
    ];
    final hasMore = items.length > limit;
    return Page(items: hasMore ? items.sublist(0, limit) : items, hasMore: hasMore);
  }

  @override
  Future<void> markThreadRead({required String userId, required String threadId, required String cursor}) async {
    final position = ChangeCursor.parse(cursor);
    final rows = await _pool.execute(
      _markThreadRead.toSql(),
      parameters: {'userId': userId, 'threadId': threadId, 'xid': position.xid, 'itemId': position.id},
    );
    switch (rows.single.toColumnMap()) {
      case {'forbidden': true}:
        throw _notYourThread;
      case {'stale': true}:
        throw _staleCursor;
    }
  }

  /// The same answer for a thread that doesn't exist, one between other people, and
  /// one whose other person blocked the caller.
  Forbidden get _notYourThread => const Forbidden(reason: 'You do not have permission to read this thread.');

  /// A cursor from before the database moved, or one no read handed out: a read
  /// position there would hide everything until the counter caught up.
  BadRequest get _staleCursor => const BadRequest(
    code: 'stale_cursor',
    reason: 'this cursor is not one a read of this thread returned; read again without it',
  );

  @override
  Future<String?> clearThread({required String userId, required String threadId}) async {
    final rows = await _pool.execute(_clearThread.toSql(), parameters: {'userId': userId, 'threadId': threadId});
    return switch (rows.firstOrNull?.toColumnMap()) {
      null => throw const Forbidden(reason: 'You do not have permission to clear this thread.'),
      final row => row['other_id'] as String?,
    };
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
    return switch (rows.firstOrNull?.toColumnMap()) {
      null => throw NotFound(type: 'Connection', id: connectionId),
      {'taken': true} => throw _idTaken,
      final row => CoachNote.fromRow(row),
    };
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
