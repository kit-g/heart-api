part of 'inputs.dart';

class ExercisePreferenceSaveIn {
  final ExercisePreference preference;

  const ExercisePreferenceSaveIn._({required this.preference});

  static Future<ExercisePreferenceSaveIn> fromRequest(Request req) async {
    final json = await req.json();
    try {
      return ExercisePreferenceSaveIn._(preference: ExercisePreference.fromJson(json));
    } on ArgumentError catch (e) {
      throw BadRequest(reason: e.toString());
    }
  }
}

class ExercisePreferenceDeleteQuery {
  final ExercisePreferenceField field;

  const ExercisePreferenceDeleteQuery._({required this.field});

  factory ExercisePreferenceDeleteQuery.fromRequest(Request req) {
    return ExercisePreferenceDeleteQuery._(
      field: req.queryParameters.raw.parsed('pref', ExercisePreferenceField.fromString),
    );
  }
}
