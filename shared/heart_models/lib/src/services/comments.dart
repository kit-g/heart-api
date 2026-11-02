import '../models/comment.dart';
import '../models/pagination.dart';

abstract interface class CommentService {
  Future<Comment> createComment({
    required String authorId,
    required CommentTarget targetType,
    required String targetId,
    required String body,
  });

  Future<Page<Comment>> listComments({
    required CommentTarget targetType,
    required String targetId,
    String? cursor,
    int limit = 20,
  });

  Future<Comment> editComment({
    required String commentId,
    required String authorId,
    required String body,
  });

  Future<void> deleteComment({
    required String commentId,
    required String authorId,
  });

  /// Returns the user_id of the workout that ultimately owns the given target.
  /// `null` if the target doesn't exist.
  Future<String?> ownerOfTarget({
    required CommentTarget targetType,
    required String targetId,
  });

  /// Who owns the target and how [readerId] stands towards it: [related] when
  /// any relationship lets them read that owner, [readable] when it reaches this
  /// target too. `null` if the target doesn't exist.
  Future<({String ownerId, bool related, bool readable})?> accessOfTarget({
    required String readerId,
    required CommentTarget targetType,
    required String targetId,
  });
}
