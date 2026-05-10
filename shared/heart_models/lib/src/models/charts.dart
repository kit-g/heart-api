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

  const ChartPreferenceType(this.value);

  factory ChartPreferenceType.fromString(String v) {
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

  factory ChartPreference.fromRow(Map row) {
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

  factory ChartPreference.exercise(String exerciseName, ChartPreferenceType type) {
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

  const _ChartPreference({
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
