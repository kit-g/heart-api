import 'package:heart_models/heart_models.dart';

abstract interface class ApiAnomalyService implements AnomalyService {
  /// [userId]'s pending anomalies whose workout started within [from]
  /// (inclusive) and [to] (exclusive), oldest first: the ones an aggregate of
  /// that window was folded from unexamined.
  Future<List<Anomaly>> getPendingAnomalies({required String userId, DateTime? from, DateTime? to});
}

extension AnomalyWarnings on Iterable<Anomaly> {
  /// The anomalies as a response's `warnings`: enough to name the entry and
  /// why, for whoever reads the counts.
  List<Map<String, dynamic>> toWarnings() {
    return [
      for (final anomaly in this)
        {
          'reason': anomaly.reason,
          'workoutId': anomaly.workoutId,
          'setId': ?anomaly.setId,
          'exerciseId': ?anomaly.exerciseId,
          'exerciseName': ?anomaly.exerciseName,
          'observed': anomaly.observed,
          'typical': ?anomaly.typical,
        },
    ];
  }
}
