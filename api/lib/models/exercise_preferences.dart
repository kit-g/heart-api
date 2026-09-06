import 'package:heart_models/heart_models.dart';

/// API-side extension of the shared [ExercisePreferenceService]: the read
/// (heart-api#73) has no natural home in the shared interface because the app
/// implements that interface for its own local database, and an added
/// abstract method there would be a breaking change (see `creates.dart` for
/// the same reasoning applied to the idempotent-create sub-interfaces).
abstract interface class ApiExercisePreferenceService implements ExercisePreferenceService {
  /// Every `(user, exercise)` row with at least one of `unitSystem`/`restTimer`
  /// set — a chart-only row is excluded, ordered by `exerciseId`.
  ///
  /// Named distinctly from `ChartPreferenceService.getPreferences` (which
  /// returns `Iterable<ChartPreference>`): `Database` implements both
  /// interfaces, and Dart cannot merge two same-named methods that differ only
  /// by return type into one class.
  Future<Iterable<ExercisePreference>> getExercisePreferences(String userId);
}

abstract interface class ExercisePreferenceResponse implements Model {
  Iterable<ExercisePreference> get preferences;

  factory({required Iterable<ExercisePreference> preferences}) = _ExercisePreferenceResponse.new;
}

class _ExercisePreferenceResponse implements ExercisePreferenceResponse {
  @override
  final Iterable<ExercisePreference> preferences;

  new({required this.preferences});

  @override
  Map<String, dynamic> toMap() {
    return {
      'preferences': preferences.map((each) => each.toMap()).toList(),
    };
  }
}
