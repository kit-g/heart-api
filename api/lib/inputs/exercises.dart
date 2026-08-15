part of 'inputs.dart';

class ExerciseCreateIn {
  final String name;
  final String category;
  final String target;
  final String? instructions;

  const new _({
    required this.name,
    required this.category,
    required this.target,
    required this.instructions,
  });

  static Future<ExerciseCreateIn> fromRequest(Request req) async {
    final json = await req.json();
    return ExerciseCreateIn._(
      name: switch (json.string('name', maxLength: 200).trim()) {
        String s when s.isNotEmpty => s,
        _ => throw const BadRequest(reason: 'name must be a non-empty string'),
      },
      category: json.string('category', maxLength: 100),
      target: json.string('target', maxLength: 100),
      instructions: json.stringOrNull('instructions', maxLength: 10000),
    );
  }
}

class ExerciseUpdateIn {
  final String? category;
  final String? target;
  final String? instructions;
  final bool? archived;

  const new _({
    required this.category,
    required this.target,
    required this.instructions,
    required this.archived,
  });

  static Future<ExerciseUpdateIn> fromRequest(Request req) async {
    final json = await req.json();
    return ExerciseUpdateIn._(
      category: json.stringOrNull('category', maxLength: 100),
      target: json.stringOrNull('target', maxLength: 100),
      instructions: json.stringOrNull('instructions', maxLength: 10000),
      archived: json.booleanOrNull('archived'),
    );
  }
}
