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
      id: json.uuidV7OrNull(),
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

/// `POST /exercises/:exerciseId/moves` — move everything the user has under the
/// exercise in the path onto `targetId`, the body's one key. `?dryRun=true`
/// previews the counts without writing. Both ids are uuids; moving an
/// exercise onto itself is refused here (`same_exercise`) before it costs a
/// round trip.
class ExerciseMoveIn {
  final String sourceId;
  final String targetId;
  final bool dryRun;

  const new _({
    required this.sourceId,
    required this.targetId,
    required this.dryRun,
  });

  static Future<ExerciseMoveIn> fromRequest(Request req, {required String sourceId}) async {
    if (!isUuidV7(sourceId)) throw const BadRequest(reason: 'the exercise id must be a UUIDv7');
    final json = await req.json();
    final targetId = switch (json.uuidV7OrNull('targetId')) {
      final String id => id,
      null => throw const BadRequest(reason: 'targetId is required'),
    };
    if (targetId == sourceId) {
      throw const BadRequest(code: 'same_exercise', reason: 'source and target are the same exercise');
    }
    return ExerciseMoveIn._(
      sourceId: sourceId,
      targetId: targetId,
      dryRun: req.url.queryParameters.boolean('dryRun'),
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
