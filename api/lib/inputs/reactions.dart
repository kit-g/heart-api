part of 'inputs.dart';

/// The words a reaction can be. The vocabulary is open on the wire and in the
/// table, so a word is added here and nowhere else; an app that doesn't know
/// one shows it as a reaction all the same.
const reactionKinds = {'cheer', 'like'};

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

/// `PUT /reactions/:targetType/:targetId`: `{kind}`.
class ReactionSetIn {
  final String kind;

  const new _(this.kind);

  static Future<ReactionSetIn> fromRequest(Request req) async {
    final json = await req.json();
    return switch (json['kind']) {
      final String kind when reactionKinds.contains(kind) => ReactionSetIn._(kind),
      _ => throw BadRequest(
        code: 'invalid_kind',
        reason: 'kind must be one of ${reactionKinds.join(', ')}',
      ),
    };
  }
}

/// `GET /reactions/:targetType/:targetId?cursor=&limit=`.
class ReactionsQuery {
  final String? cursor;
  final int limit;

  const new _({required this.cursor, required this.limit});

  static ReactionsQuery fromRequest(Request req) {
    final query = req.url.queryParameters;
    final cursor = query.stringOrNull('cursor');
    if (cursor != null && !isUuidV7(cursor)) {
      throw const BadRequest(reason: 'cursor must be the one the previous page returned');
    }
    return ReactionsQuery._(cursor: cursor, limit: query.integer('limit', defaultValue: 50, min: 1, max: 100));
  }
}
