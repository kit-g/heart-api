import '../models/anomaly.dart';
import '../models/pagination.dart';

abstract interface class AnomalyService {
  /// [userId]'s anomalies, newest found first, [limit] at a time after the
  /// anomaly id [cursor]; only those of [status] when given.
  Future<Page<Anomaly>> getAnomalies({required String userId, AnomalyStatus? status, String? cursor, int limit});

  /// Records what the user made of one anomaly, replacing an earlier
  /// decision. Null when [userId] has no anomaly [anomalyId].
  Future<Anomaly?> resolveAnomaly({required String userId, required String anomalyId, required AnomalyStatus status});
}
