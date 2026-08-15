part of 'inputs.dart';

const _maxCommentBody = 5000;

class CommentCreateIn {
  final CommentTarget targetType;
  final String targetId;
  final String body;

  const new _({required this.targetType, required this.targetId, required this.body});

  static Future<CommentCreateIn> fromRequest(Request req) async {
    final json = await req.json();
    return CommentCreateIn._(
      targetType: json.parsed('targetType', CommentTarget.fromString),
      targetId: json.string('targetId'),
      body: json.string('body', maxLength: _maxCommentBody),
    );
  }
}

class CommentEditIn {
  final String commentId;
  final String body;

  const new _({required this.commentId, required this.body});

  static Future<CommentEditIn> fromRequest(Request req, {required String commentId}) async {
    final json = await req.json();
    return CommentEditIn._(
      commentId: commentId,
      body: json.string('body', maxLength: _maxCommentBody),
    );
  }
}

class CommentsListQuery {
  final CommentTarget targetType;
  final String targetId;
  final String? cursor;
  final int limit;

  const new _({
    required this.targetType,
    required this.targetId,
    required this.cursor,
    required this.limit,
  });

  static CommentsListQuery fromRequest(Request req) {
    final q = req.url.queryParameters;
    return CommentsListQuery._(
      targetType: q.parsed('targetType', CommentTarget.fromString),
      targetId: q.string('targetId'),
      cursor: q.stringOrNull('cursor'),
      limit: q.integer('limit', defaultValue: 20, min: 1, max: 50),
    );
  }
}
