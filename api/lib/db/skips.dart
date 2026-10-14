part of 'db.dart';

mixin _Skips on _DatabaseBase implements SkipService {
  @override
  Future<Page<TrainingSkip>> getSkips({required String userId, String? cursor, int limit = 30}) async {
    // One extra row so hasMore is authoritative without a second query.
    final rows = await _pool.execute(
      _listSkips.toSql(),
      parameters: {'userId': userId, 'cursor': cursor, 'limit': limit + 1},
    );
    final skips = rows.map((row) => TrainingSkip.fromRow(row.toColumnMap())).toList();
    final hasMore = skips.length > limit;
    return Page(items: hasMore ? skips.sublist(0, limit) : skips, hasMore: hasMore);
  }

  @override
  Future<(TrainingSkip, bool created)> createSkip({required String userId, required TrainingSkip skip}) async {
    try {
      final rows = await _retryOnCreateRace(
        () => _pool.execute(
          _createSkip.toSql(),
          parameters: {
            'id': skip.id,
            'userId': userId,
            'at': skip.at.toUtc(),
            'reason': skip.reason,
            'weather': switch (skip.weather) {
              final Weather weather when !weather.isEmpty => jsonEncode(weather.toMap()),
              _ => null,
            },
            'templateId': skip.templateId,
            'programId': skip.programId,
          },
        ),
      );
      if (rows.isEmpty) {
        throw const BadRequest(code: 'skip_limit', reason: 'you can keep at most $_maxSkips skips');
      }
      final row = rows.first.toColumnMap();
      return (TrainingSkip.fromRow(row), row['created'] as bool);
    } on ServerException catch (e) {
      _rethrowForeignId(e);
    }
  }

  @override
  Future<void> deleteSkip({required String userId, required String skipId}) async {
    await _pool.execute(_deleteSkip.toSql(), parameters: {'id': skipId, 'userId': userId});
  }
}
