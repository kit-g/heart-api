part of 'db.dart';

mixin _Comments on _DatabaseBase implements CommentService {
  @override
  Future<Comment> createComment({
    required String authorId,
    required CommentTarget targetType,
    required String targetId,
    required String body,
  }) async {
    final result = await _pool.execute(
      _insertComment.toSql(),
      parameters: {
        'authorId': authorId,
        'body': body,
        'targetType': targetType.value,
        'targetId': targetId,
      },
    );
    if (result.isEmpty) throw NotFound(type: 'comment target', id: targetId);
    return Comment.fromRow(result.first.toColumnMap());
  }

  @override
  Future<Page<Comment>> listComments({
    required CommentTarget targetType,
    required String targetId,
    String? cursor,
    int limit = 20,
  }) async {
    // fetch one extra row so we can report hasMore without a second query.
    final result = await _pool.execute(
      _listComments.toSql(),
      parameters: {
        'targetType': targetType.value,
        'targetId': targetId,
        'cursor': cursor,
        'limit': limit + 1,
      },
    );
    final rows = result.map((r) => Comment.fromRow(r.toColumnMap())).toList();
    final hasMore = rows.length > limit;
    return Page(items: hasMore ? rows.sublist(0, limit) : rows, hasMore: hasMore);
  }

  @override
  Future<Comment> editComment({
    required String commentId,
    required String authorId,
    required String body,
  }) async {
    final result = await _pool.execute(
      _updateComment.toSql(),
      parameters: {
        'commentId': commentId,
        'authorId': authorId,
        'body': body,
      },
    );
    if (result.isEmpty) throw NotFound(type: 'comment', id: commentId);
    return Comment.fromRow(result.first.toColumnMap());
  }

  @override
  Future<void> deleteComment({
    required String commentId,
    required String authorId,
  }) async {
    final result = await _pool.execute(
      _deleteComment.toSql(),
      parameters: {
        'commentId': commentId,
        'authorId': authorId,
      },
    );
    if (result.isEmpty) throw NotFound(type: 'comment', id: commentId);
  }

  @override
  Future<String?> ownerOfTarget({
    required CommentTarget targetType,
    required String targetId,
  }) async {
    final result = await _pool.execute(
      _resolveCommentTargetOwner.toSql(),
      parameters: {
        'targetType': targetType.value,
        'targetId': targetId,
      },
    );
    if (result.isEmpty) return null;
    return result.first[0] as String;
  }
}