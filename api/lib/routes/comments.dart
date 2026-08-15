import 'package:heart/globals/config.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/inputs/inputs.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/middleware/events.dart';
import 'package:heart/models/errors.dart';
import 'package:heart/models/pagination.dart';
import 'package:heart/notifications/renderer.dart';
import 'package:heart_models/heart_models.dart';
import 'package:relic/relic.dart';

Future<Comment> createComment(Request req) async {
  final input = await CommentCreateIn.fromRequest(req);
  final ownerId = await _assertCanAccessTarget(req, targetType: input.targetType, targetId: input.targetId);
  final comment = await req.commentService.createComment(
    authorId: req.userId,
    targetType: input.targetType,
    targetId: input.targetId,
    body: input.body,
  );

  // Skip self-notification — you don't push to yourself for commenting on
  // your own content.
  if (req.userId != ownerId) {
    await req.events.publish(
      queueUrl: req.config.eventsQueueUrl,
      message: {
        'type': 'comment.created',
        'commentId': comment.id,
        'authorId': req.userId,
        'authorName': req.user.displayName ?? 'Someone',
        'ownerId': ownerId,
        'targetType': input.targetType.value,
        'targetId': input.targetId,
        'body': snippetize(input.body),
      },
    );
  }

  return comment;
}

Future<Model> listComments(Request req) async {
  final input = CommentsListQuery.fromRequest(req);
  await _assertCanAccessTarget(req, targetType: input.targetType, targetId: input.targetId);
  final page = await req.commentService.listComments(
    targetType: input.targetType,
    targetId: input.targetId,
    cursor: input.cursor,
    limit: input.limit,
  );
  return Paginated<Comment>.from(page, itemsKey: 'comments', cursorOf: (c) => c.id);
}

Future<Comment> editComment(Request req) => editCommentById(req, req.rawPathParameters[#commentId]!);

Future<Comment> editCommentById(Request req, String commentId) async {
  final input = await CommentEditIn.fromRequest(req, commentId: commentId);
  return req.commentService.editComment(
    commentId: input.commentId,
    authorId: req.userId,
    body: input.body,
  );
}

Future<Model> deleteComment(Request req) => deleteCommentById(req, req.rawPathParameters[#commentId]!);

Future<Model> deleteCommentById(Request req, String commentId) async {
  await req.commentService.deleteComment(commentId: commentId, authorId: req.userId);
  throw const NoContent();
}

/// Ensures the caller can read/write comments on the given target. Returns
/// the resolved owner user id (the workout author) so the caller can use it
/// for downstream side-effects (e.g. building a notification event).
Future<String> _assertCanAccessTarget(
  Request req, {
  required CommentTarget targetType,
  required String targetId,
}) async {
  final ownerId = await req.commentService.ownerOfTarget(
    targetType: targetType,
    targetId: targetId,
  );
  if (ownerId == null) throw NotFound(type: targetType.value, id: targetId);
  if (ownerId == req.userId) return ownerId;
  final connected = await req.connectionsService.areConnected(
    userA: req.userId,
    userB: ownerId,
  );
  if (!connected) {
    throw const Forbidden(reason: 'not connected to the owner of this content');
  }
  return ownerId;
}
