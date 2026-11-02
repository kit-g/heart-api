part of 'db.dart';

mixin _Roster on _DatabaseBase implements RosterService {
  @override
  Future<List<DirtySummary>> getDirtySummaries({required String coachId, int limit = 200}) async {
    final rows = await _pool.execute(_dirtySummaries.toSql(), parameters: {'coachId': coachId, 'limit': limit});
    return [
      for (final row in rows.map((row) => row.toColumnMap()))
        (
          connectionId: row['connection_id'].toString(),
          coachId: coachId,
          studentId: row['student_id'] as String,
          generation: row['generation'] as int,
          program: row['id'] == null ? null : Program.fromRow(row),
        ),
    ];
  }

  @override
  Future<void> refreshSummary({
    required String connectionId,
    required String coachId,
    required String studentId,
    required int generation,
    String? programId,
    String? programName,
    int? programWeek,
    int? programWeeks,
    required bool ending,
  }) async {
    await _pool.execute(
      _refreshSummary.toSql(),
      parameters: {
        'connectionId': connectionId,
        'coachId': coachId,
        'studentId': studentId,
        'generation': generation,
        'programId': programId,
        'programName': programName,
        'programWeek': programWeek,
        'programWeeks': programWeeks,
        'ending': ending,
      },
    );
  }

  @override
  Future<Page<ClientSummary>> getRoster({
    required String coachId,
    String? reason,
    bool former = false,
    String? cursor,
    int limit = 50,
  }) async {
    final after = switch (cursor?.split(':')) {
      null => null,
      [final rank, final id] when int.tryParse(rank) != null && isUuidV7(id) => (rank: int.parse(rank), id: id),
      _ => throw const BadRequest(reason: 'cursor is not one from this list'),
    };
    final rows = await _pool.execute(
      _roster.toSql(),
      parameters: {
        'coachId': coachId,
        'reason': reason,
        'former': former,
        'afterRank': after?.rank,
        'afterId': after?.id,
        'limit': limit + 1,
      },
    );
    final maps = rows.map((row) => row.toColumnMap()).toList();
    final items = [for (final row in maps) ClientSummary.fromRow(row)];
    final hasMore = items.length > limit;
    return Page(items: hasMore ? items.sublist(0, limit) : items, hasMore: hasMore);
  }

  @override
  Future<void> markReviewed({required String coachId, required String connectionId, DateTime? at}) async {
    await _pool.execute(
      _markReviewed.toSql(),
      parameters: {'coachId': coachId, 'connectionId': connectionId, 'at': at?.toUtc()},
    );
  }

  @override
  Future<Page<CoachFeedItem>> getCoachFeed({required String coachId, String? cursor, int limit = 50}) async {
    final after = switch (cursor?.split('|')) {
      null => null,
      [final at, final id] when DateTime.tryParse(at) != null => (at: DateTime.parse(at), id: id),
      _ => throw const BadRequest(reason: 'cursor is not one from this feed'),
    };
    final rows = await _pool.execute(
      _coachFeed.toSql(),
      parameters: {'coachId': coachId, 'afterAt': after?.at, 'afterId': after?.id, 'limit': limit + 1},
    );
    final items = [
      for (final row in rows.map((row) => row.toColumnMap()))
        CoachFeedItem.fromRow(row, cursor: '${(row['at'] as DateTime).toUtc().toIso8601String()}|${row['id']}'),
    ];
    final hasMore = items.length > limit;
    return Page(items: hasMore ? items.sublist(0, limit) : items, hasMore: hasMore);
  }
}
