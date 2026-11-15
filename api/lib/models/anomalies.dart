import 'package:heart_models/heart_models.dart';

import 'changes.dart';

/// Each takes a `locale` to name an anomaly's exercise in, as `ApiWorkoutService`
/// does; null is the library's own name.
abstract interface class ApiAnomalyService implements AnomalyService {
  /// [userId]'s pending anomalies whose workout started within [from]
  /// (inclusive) and [to] (exclusive), oldest first: the ones an aggregate of
  /// that window was folded from unexamined.
  Future<List<Anomaly>> getPendingAnomalies({required String userId, DateTime? from, DateTime? to, String? locale});

  @override
  Future<Page<Anomaly>> getAnomalies({
    required String userId,
    AnomalyStatus? status,
    String? cursor,
    int limit,
    String? locale,
  });

  @override
  Future<Anomaly?> resolveAnomaly({
    required String userId,
    required String anomalyId,
    required AnomalyStatus status,
    String? locale,
  });
}

extension AnomalyWarnings on Iterable<Anomaly> {
  /// Those on [exerciseId]'s sets in the [sessions] shown: the warnings of a
  /// page of its history.
  List<Anomaly> onSessions(String exerciseId, Iterable<ExerciseSession> sessions) {
    final shown = {for (final session in sessions) session.workoutId};
    return [
      for (final anomaly in this)
        if (anomaly.exerciseId == exerciseId && shown.contains(anomaly.workoutId)) anomaly,
    ];
  }

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
