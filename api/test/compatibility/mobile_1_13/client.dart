import 'dart:convert';
import 'dart:io';

import 'package:heart_models/heart_models.dart';

/// Runs in a separate process so the server and the installed client's models
/// cannot silently upgrade together. stdin/stdout carry only synthetic fixtures.
Future<void> main(List<String> args) async {
  final input = jsonDecode(await stdin.transform(utf8.decoder).join()) as Map<String, dynamic>;
  final output = switch (args.single) {
    'workout' => _workout(input),
    'library' => {
      'exercises': [
        for (final row in (input['exercises'] as List).cast<Map>()) _exercise(Exercise.fromJson(row)),
      ],
    },
    _ => throw ArgumentError('unknown contract operation'),
  };
  stdout.write(jsonEncode(output));
}

Map<String, dynamic> _workout(Map<String, dynamic> input) {
  final workout = Workout.fromJson(input);
  return {
    'save': workout.toMap(),
    'unread': workout.unread.length,
    'exercises': [
      for (final exercise in workout)
        {
          ..._exercise(exercise.exercise),
          'unread': exercise.unread.length,
          'sets': [for (final set in exercise) set.toMap()],
        },
    ],
  };
}

Map<String, dynamic> _exercise(Exercise exercise) => {
  'id': exercise.id,
  'key': exercise.key,
  'name': exercise.name,
  'category': exercise.category.value,
  'target': exercise.target.value,
};
