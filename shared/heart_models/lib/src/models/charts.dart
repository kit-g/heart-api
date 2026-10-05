import 'dart:convert';

import 'exercise.dart' show Category;
import 'misc.dart';

enum ChartPreferenceType {
  maxConsecutiveReps('maxConsecutiveReps'),
  topSetWeight('topSetWeight'),
  estimatedOneRepMax('estimatedOneRepMax'),
  totalVolume('totalVolume'),
  averageWorkingWeight('averageWorkingWeight'),
  assistanceWeight('assistanceWeight'),
  totalReps('totalReps'),
  cardioDistance('cardioDistance'),
  cardioDuration('cardioDuration'),
  averagePace('averagePace'),
  totalTimeUnderTension('totalTimeUnderTension'),
  ;

  final String value;

  new(this.value);

  factory fromString(String v) {
    return switch (v) {
      'maxConsecutiveReps' => maxConsecutiveReps,
      'topSetWeight' => topSetWeight,
      'estimatedOneRepMax' => estimatedOneRepMax,
      'totalVolume' => totalVolume,
      'averageWorkingWeight' => averageWorkingWeight,
      'assistanceWeight' => assistanceWeight,
      'totalReps' => totalReps,
      'cardioDistance' => cardioDistance,
      'cardioDuration' => cardioDuration,
      'averagePace' => averagePace,
      'totalTimeUnderTension' => totalTimeUnderTension,
      _ => throw ArgumentError(v),
    };
  }

  /// Whether this dimension's values are durations, in seconds.
  bool get isDuration => this == cardioDuration || this == totalTimeUnderTension;

  /// How the sessions inside one period fold into the single number a
  /// recurring goal is measured by.
  ///
  /// "Per week" does not mean the same arithmetic for every dimension: 2000 kg
  /// of volume a week is a total you accumulate, while a 100 kg top set a week
  /// is the week's best lift — summing every session's top set would say you
  /// had pressed 300 kg.
  PeriodAggregate get periodAggregate {
    return switch (this) {
      // quantities that accumulate across the period
      .totalVolume || .totalReps || .totalTimeUnderTension || .cardioDistance || .cardioDuration => .sum,
      // peaks: the best single session in the period, not a running total.
      // Assistance is the odd one — less of it is the improvement — but only
      // pace is `lowerIsBetter`, so it follows the other weights rather than
      // inventing a second direction here.
      .topSetWeight || .estimatedOneRepMax || .maxConsecutiveReps || .assistanceWeight => .best,
      // already a per-session average, so the period averages those
      .averageWorkingWeight || .averagePace => .mean,
    };
  }

  static List<ChartPreferenceType> chartsByExerciseCategory(Category category) {
    switch (category) {
      case .weightedBodyWeight:
        return const [
          .topSetWeight,
          .totalVolume,
          .estimatedOneRepMax,
          .averageWorkingWeight,
          .totalReps,
          .maxConsecutiveReps,
        ];

      case .assistedBodyWeight:
        return const [
          .assistanceWeight,
          .topSetWeight,
          .totalVolume,
          .averageWorkingWeight,
          .totalReps,
          .maxConsecutiveReps,
        ];

      case .repsOnly:
        return const [.maxConsecutiveReps, .totalReps];

      case .cardio:
        return const [.cardioDistance, .cardioDuration, .averagePace];

      case .duration:
        return const [.totalTimeUnderTension];

      case .weightedDistance:
        return const [.topSetWeight, .cardioDistance];

      case .weightedDuration:
        return const [.topSetWeight, .totalTimeUnderTension];

      case .machine:
      case .dumbbell:
      case .barbell:
        return const [
          .topSetWeight,
          .estimatedOneRepMax,
          .totalVolume,
          .averageWorkingWeight,
          .totalReps,
          .maxConsecutiveReps,
        ];
    }
  }
}

/// How several sessions in one period become one number. See
/// [ChartPreferenceType.periodAggregate] for which dimension folds which way.
enum PeriodAggregate {
  sum,
  best,
  mean;

  /// [values] must not be empty — an empty period has no aggregate, and what
  /// to show instead is the caller's decision.
  num of(Iterable<num> values) {
    return switch (this) {
      sum => values.reduce((a, b) => a + b),
      best => values.reduce((a, b) => a > b ? a : b),
      mean => values.reduce((a, b) => a + b) / values.length,
    };
  }
}

abstract interface class ChartPreference implements Storable, Model {
  String? get id;

  ChartPreferenceType get type;

  Map<String, dynamic>? get data;

  String? get exerciseName;

  ChartPreference copyWith({
    String? id,
    ChartPreferenceType? type,
    Map<String, dynamic>? data,
  });

  factory fromRow(Map row) {
    return _ChartPreference(
      id: row['id']?.toString(),
      type: ChartPreferenceType.fromString(row['type']),
      data: switch (row['data']) {
        String raw => jsonDecode(raw),
        Map m => m,
        null => null,
        _ => throw ArgumentError(row),
      },
    );
  }

  /// Builds a preference from already-validated parts (e.g. a typed API
  /// input). [ChartPreference.fromRow] remains the DB-row parser.
  factory create({
    String? id,
    required ChartPreferenceType type,
    Map<String, dynamic>? data,
  }) {
    return _ChartPreference(id: id, type: type, data: data);
  }

  factory exercise(String exerciseName, ChartPreferenceType type) {
    return _ChartPreference(
      id: null,
      type: type,
      data: {'exerciseName': exerciseName},
    );
  }
}

class _ChartPreference implements ChartPreference {
  @override
  final String? id;
  @override
  final ChartPreferenceType type;
  @override
  final Map<String, dynamic>? data;

  const new({
    this.id,
    required this.type,
    required this.data,
  });

  @override
  Map<String, dynamic> toRow() {
    return {
      'id': id,
      'type': type.value,
      'data': ?switch (data) {
        Map<String, dynamic> d => jsonEncode(d),
        null => null,
      },
    };
  }

  @override
  ChartPreference copyWith({
    String? id,
    ChartPreferenceType? type,
    Map<String, dynamic>? data,
  }) {
    return _ChartPreference(
      type: type ?? this.type,
      data: data ?? this.data,
      id: id ?? this.id,
    );
  }

  @override
  String? get exerciseName => data?['exerciseName'];

  @override
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type.value,
      'data': ?data,
    };
  }
}
