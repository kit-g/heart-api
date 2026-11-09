part of 'inputs.dart';

/// The words a reaction can be. The vocabulary is open on the wire and in the
/// table, so a word is added here and nowhere else; an app that doesn't know
/// one shows it as a reaction all the same.
const _reactionKinds = {'cheer', 'like'};

/// The target in `/reactions/:targetType/:targetId`, checked before anything casts
/// it: one that can't be a target answers like one that isn't there.
extension ReactionPaths on Request {
  ({ReactionTarget type, String id}) get reactionTarget {
    final type = rawPathParameters[#targetType]!;
    final id = rawPathParameters[#targetId]!;
    try {
      if (isUuidV7(id)) return (type: CommentTarget.fromString(type), id: id);
    } on ArgumentError {
      // an unknown target type falls through to the same answer as a bad id
    }
    throw NotFound(type: type, id: id);
  }
}

/// `PUT /reactions/:targetType/:targetId`: `{kind, at?}`, `at` being when the
/// person reacted, by their device, so a reaction made offline keeps its time.
class ReactionSetIn {
  final String kind;
  final DateTime? at;

  const new _(this.kind, this.at);

  static Future<ReactionSetIn> fromRequest(Request req) async {
    final json = await req.json();
    final kind = switch (json['kind']) {
      final String kind when _reactionKinds.contains(kind) => kind,
      _ => throw BadRequest(code: 'invalid_kind', reason: 'kind must be one of ${_reactionKinds.join(', ')}'),
    };
    final at = switch (json['at']) {
      null => null,
      final String at when DateTime.tryParse(at) != null => DateTime.parse(at),
      _ => throw const BadRequest(reason: 'at must be an ISO-8601 time'),
    };
    return ReactionSetIn._(kind, at);
  }
}

/// `GET /reactions/:targetType/:targetId?cursor=&limit=`.
extension type const ReactionsQuery._(PageQuery page) {
  static ReactionsQuery fromRequest(Request req) {
    final page = PageQuery.fromRequest(req, defaultLimit: 50);
    if (page.cursor case final cursor? when !isUuidV7(cursor)) {
      throw const BadRequest(reason: 'cursor must be the one the previous page returned');
    }
    return ReactionsQuery._(page);
  }
}
