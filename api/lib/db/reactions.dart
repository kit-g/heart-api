part of 'db.dart';

mixin _Reactions on _DatabaseBase implements ReactionService {
  @override
  Future<({Reaction reaction, bool created, String? notify})> setReaction({
    required String authorId,
    required ReactionTarget targetType,
    required String targetId,
    required String kind,
    DateTime? at,
  }) async {
    final rows = await _pool.execute(
      _setReactionSql[targetType]!.toSql(),
      parameters: {
        'authorId': authorId,
        'readerId': authorId,
        'targetType': targetType.value,
        'targetId': targetId,
        'kind': kind,
        'at': at?.toUtc(),
      },
    );
    final row = _readable(rows, targetType, targetId);
    return (reaction: Reaction.fromRow(row), created: row['created'] as bool, notify: row['notify'] as String?);
  }

  @override
  Future<void> removeReaction({
    required String authorId,
    required ReactionTarget targetType,
    required String targetId,
  }) async {
    await _pool.execute(
      _removeReactionSql[targetType]!.toSql(),
      parameters: {'authorId': authorId, 'targetId': targetId},
    );
  }

  @override
  Future<({Page<Reaction> page, ReactionSummary summary})> getReactions({
    required String readerId,
    required ReactionTarget targetType,
    required String targetId,
    String? cursor,
    int limit = 50,
  }) async {
    final rows = await _pool.execute(
      _getReactionsSql[targetType]!.toSql(),
      parameters: {
        'readerId': readerId,
        'targetType': targetType.value,
        'targetId': targetId,
        'cursor': cursor,
        'limit': limit + 1,
      },
    );
    final row = _readable(rows, targetType, targetId);
    final reactions = [for (final each in row['page'] as List) Reaction.fromRow((each as Map).cast<String, dynamic>())];
    final hasMore = reactions.length > limit;
    return (
      page: Page(items: hasMore ? reactions.sublist(0, limit) : reactions, hasMore: hasMore),
      summary: (
        counts: {
          for (final MapEntry(:key, :value) in (row['counts'] as Map).entries) '$key': (value as num).toInt(),
        },
        mine: row['mine'] as String?,
      ),
    );
  }

  /// The comments' answers: a stranger is refused, and what the reader can't see
  /// doesn't exist for them.
  static Map<String, dynamic> _readable(Result rows, ReactionTarget target, String id) {
    return switch (rows.firstOrNull?.toColumnMap()) {
      null => throw NotFound(type: target.value, id: id),
      {'related': false} => throw const Forbidden(reason: 'not connected to the owner of this content'),
      {'readable': false} => throw NotFound(type: target.value, id: id),
      final row => row,
    };
  }
}
