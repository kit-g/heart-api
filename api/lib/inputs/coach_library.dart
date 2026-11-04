part of 'inputs.dart';

/// `PUT /library-programs/:programId`: a program and its sessions, as `POST
/// /programs` takes them. Saved as a document, with every row given an id.
class CoachProgramIn {
  final String id;
  final String name;
  final Map<String, dynamic> body;

  const new _({required this.id, required this.name, required this.body});

  static Future<CoachProgramIn> fromRequest(Request req, {required String id}) async {
    if (!isUuidV7(id)) throw const BadRequest(reason: 'id must be a UUIDv7');
    final json = await req.json();
    final program = ProgramCreateIn.fromJson(req.userId, json);
    return CoachProgramIn._(id: id, name: program.program.name, body: withRowIds(json)..remove('id'));
  }
}

/// `POST /library-programs/:programId/send` — `{connectionIds: [...]}`.
class CoachProgramSendIn {
  final List<String> connectionIds;

  const new _(this.connectionIds);

  static Future<CoachProgramSendIn> fromRequest(Request req) async {
    final json = await req.json();
    return switch (json['connectionIds']) {
      final List ids when ids.isNotEmpty && ids.length <= 100 && ids.every((id) => id is String && isUuidV7(id)) =>
        CoachProgramSendIn._(ids.cast<String>()),
      _ => throw const BadRequest(reason: 'connectionIds must be a list of at most 100 connections'),
    };
  }
}
