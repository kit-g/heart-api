part of 'db.dart';

mixin _Roster on _DatabaseBase implements RosterService {
  @override
  Future<List<DirtySummary>> getDirtySummaries({required String coachId}) async {
    final rows = await _pool.execute(_dirtySummaries.toSql(), parameters: {'coachId': coachId});
    return [
      for (final row in rows.map((row) => row.toColumnMap()))
        (
          connectionId: row['connection_id'].toString(),
          coachId: coachId,
          studentId: row['student_id'] as String,
          generation: row['generation'] as int,
          program: switch (row['id']) {
            null => null,
            _ => Program.fromRow(row),
          },
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
    OrderedCursor? cursor,
    int limit = 50,
    bool assistant = false,
  }) async {
    final rows = await _pool.execute(
      _roster.toSql(),
      parameters: {
        'assistant': assistant,
        'coachId': coachId,
        'reason': reason,
        'former': former,
        'afterRank': cursor?.order,
        'afterId': cursor?.id,
        'limit': limit + 1,
      },
    );
    final items = [for (final row in rows) ClientSummary.fromRow(row.toColumnMap())];
    final hasMore = items.length > limit;
    return Page(items: hasMore ? items.sublist(0, limit) : items, hasMore: hasMore);
  }

  @override
  Future<bool> markReviewed({required String coachId, required String connectionId, DateTime? at}) async {
    final rows = await _pool.execute(
      _markReviewed.toSql(),
      parameters: {'coachId': coachId, 'connectionId': connectionId, 'at': at?.toUtc()},
    );
    return rows.isNotEmpty;
  }

  @override
  Future<Page<CoachFeedItem>> getCoachFeed({
    required String coachId,
    FeedCursor? cursor,
    int limit = 50,
    bool assistant = false,
  }) async {
    final rows = await _pool.execute(
      _coachFeed.toSql(),
      parameters: {
        'coachId': coachId,
        'afterAt': cursor?.at.toUtc(),
        'afterId': cursor?.id,
        'limit': limit + 1,
        'assistant': assistant,
      },
    );
    final items = [
      for (final row in rows.map((row) => row.toColumnMap()))
        CoachFeedItem.fromRow(row, cursor: '${(row['at'] as DateTime).toUtc().toIso8601String()}|${row['id']}'),
    ];
    final hasMore = items.length > limit;
    return Page(items: hasMore ? items.sublist(0, limit) : items, hasMore: hasMore);
  }

  @override
  Future<bool> coaches(String userId) async {
    final rows = await _pool.execute(_coaches.toSql(), parameters: {'userId': userId});
    return rows.first[0] as bool;
  }
}
