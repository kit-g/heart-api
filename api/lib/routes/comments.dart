import 'package:heart/globals/globals.dart';
import 'package:heart/inputs/inputs.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/models/errors.dart';
import 'package:heart/models/pagination.dart';
import 'package:heart_models/heart_models.dart';
import 'package:relic/relic.dart';

Future<Comment> createComment(final Request req) async {
  final input = await CommentCreateIn.fromRequest(req);
  await _assertCanAccessTarget(req, targetType: input.targetType, targetId: input.targetId);
  return req.commentService.createComment(
    authorId: req.userId,
    targetType: input.targetType,
    targetId: input.targetId,
    body: input.body,
  );
}

Future<Model> listComments(final Request req) async {
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

Future<Comment> editComment(final Request req) => editCommentById(req, req.rawPathParameters[#commentId]!);

Future<Comment> editCommentById(final Request req, final String commentId) async {
  final input = await CommentEditIn.fromRequest(req, commentId: commentId);
  return req.commentService.editComment(
    commentId: input.commentId,
    authorId: req.userId,
    body: input.body,
  );
}

Future<Model> deleteComment(final Request req) => deleteCommentById(req, req.rawPathParameters[#commentId]!);

Future<Model> deleteCommentById(final Request req, final String commentId) async {
  await req.commentService.deleteComment(commentId: commentId, authorId: req.userId);
  throw const NoContent();
}

/// Ensures the caller can read/write comments on the given target: they're
/// either the owner of the underlying workout, or connected to that owner.
Future<void> _assertCanAccessTarget(
  Request req, {
  required CommentTarget targetType,
  required String targetId,
}) async {
  final ownerId = await req.commentService.ownerOfTarget(
    targetType: targetType,
    targetId: targetId,
  );
  if (ownerId == null) throw NotFound(type: targetType.value, id: targetId);
  if (ownerId == req.userId) return;
  final connected = await req.connectionsService.areConnected(
    userA: req.userId,
    userB: ownerId,
  );
  if (!connected) {
    throw const Forbidden(reason: 'not connected to the owner of this content');
  }
}
