part of 'inputs.dart';

class ExerciseCreateIn {
  final String? id;
  final String name;
  final String category;
  final String target;
  final String? instructions;

  const new _({
    required this.id,
    required this.name,
    required this.category,
    required this.target,
    required this.instructions,
  });

  static Future<ExerciseCreateIn> fromRequest(Request req) async {
    final json = await req.json();
    return ExerciseCreateIn._(
      // the app mints a v7 at construction and keeps it as the exercise's
      // identity through sync; present-but-malformed is the client's mistake
      id: switch (json['id']) {
        null => null,
        final String id when isUuidV7(id) => id,
        _ => throw const BadRequest(reason: 'id must be a UUIDv7'),
      },
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
