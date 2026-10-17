part of 'db.dart';

mixin _Anomalies on _DatabaseBase implements ApiAnomalyService {
  @override
  Future<Page<Anomaly>> getAnomalies({
    required String userId,
    AnomalyStatus? status,
    String? cursor,
    int limit = 30,
  }) async {
    final rows = await _pool.execute(
      _getAnomalies.toSql(),
      parameters: {'userId': userId, 'status': status?.value, 'cursor': cursor, 'limit': limit + 1},
    );
    final items = [for (final row in rows) Anomaly.fromRow(row.toColumnMap())];
    final hasMore = items.length > limit;
    return Page(items: hasMore ? items.sublist(0, limit) : items, hasMore: hasMore);
  }

  @override
  Future<List<Anomaly>> getPendingAnomalies({required String userId, DateTime? from, DateTime? to}) async {
    final rows = await _pool.execute(
      _getPendingAnomalies.toSql(),
      parameters: {'userId': userId, 'from': from, 'to': to},
    );
    return [for (final row in rows) Anomaly.fromRow(row.toColumnMap())];
  }

  @override
  Future<Anomaly?> resolveAnomaly({
    required String userId,
    required String anomalyId,
    required AnomalyStatus status,
  }) async {
    final rows = await _pool.execute(
      _resolveAnomaly.toSql(),
      parameters: {'userId': userId, 'anomalyId': anomalyId, 'status': status.value},
    );
    return switch (rows) {
      [final row] => Anomaly.fromRow(row.toColumnMap()),
      _ => null,
    };
  }
}
