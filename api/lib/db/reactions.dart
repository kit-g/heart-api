part of 'db.dart';

mixin _Reactions on _DatabaseBase implements ReactionService {
  @override
  Future<(Reaction, bool created)> setReaction({
    required String authorId,
    required ReactionTarget targetType,
    required String targetId,
    required String kind,
  }) async {
    Future<Result> attempt() => _pool.execute(
      _setReaction.toSql(),
      parameters: {'authorId': authorId, 'targetType': targetType.value, 'targetId': targetId, 'kind': kind},
    );

    // a second try sees a row the same person's other request committed meanwhile
    final rows = switch (await attempt()) {
      final Result rows when rows.isEmpty => await attempt(),
      final rows => rows,
    };
    return switch (rows.firstOrNull?.toColumnMap()) {
      null => throw NotFound(type: targetType.value, id: targetId),
      final row => (Reaction.fromRow(row), row['created'] as bool),
    };
  }

  @override
  Future<void> removeReaction({
    required String authorId,
    required ReactionTarget targetType,
    required String targetId,
  }) async {
    await _pool.execute(
      _removeReaction.toSql(),
      parameters: {'authorId': authorId, 'targetType': targetType.value, 'targetId': targetId},
    );
  }

  @override
  Future<Page<Reaction>> listReactions({
    required ReactionTarget targetType,
    required String targetId,
    String? cursor,
    int limit = 50,
  }) async {
    final rows = await _pool.execute(
      _listReactions.toSql(),
      parameters: {'targetType': targetType.value, 'targetId': targetId, 'cursor': cursor, 'limit': limit + 1},
    );
    final reactions = [for (final row in rows) Reaction.fromRow(row.toColumnMap())];
    final hasMore = reactions.length > limit;
    return Page(items: hasMore ? reactions.sublist(0, limit) : reactions, hasMore: hasMore);
  }

  @override
  Future<ReactionSummary> summarizeReactions({
    required String readerId,
    required ReactionTarget targetType,
    required String targetId,
  }) async {
    final rows = await _pool.execute(
      _summarizeReactions.toSql(),
      parameters: {'readerId': readerId, 'targetType': targetType.value, 'targetId': targetId},
    );
    final row = rows.single.toColumnMap();
    return (
      counts: {
        for (final MapEntry(:key, :value) in (row['counts'] as Map).entries) '$key': (value as num).toInt(),
      },
      mine: row['mine'] as String?,
    );
  }
}
