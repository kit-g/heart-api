import 'comment.dart';
import 'misc.dart';
import 'tolerant.dart' show readIndexed;

/// What a reaction can be on: the same things as a comment.
typedef ReactionTarget = CommentTarget;

/// One person's reaction to a workout, an exercise in it, a set, or a photo.
/// [kind] is an open vocabulary (`cheer`, `like` so far): a word this build
/// doesn't know is carried as it arrived.
abstract interface class Reaction implements Model {
  String get id;

  String get authorId;

  /// The name the author's profile holds, if any.
  String? get authorName;

  String get kind;

  ReactionTarget get targetType;

  String get targetId;

  DateTime get createdAt;

  factory({
    required String id,
    required String authorId,
    String? authorName,
    required String kind,
    required ReactionTarget targetType,
    required String targetId,
    required DateTime createdAt,
  }) = _Reaction.new;

  factory fromRow(Map<String, dynamic> row) {
    return Reaction(
      id: row['id'].toString(),
      authorId: row['author_id'] as String,
      authorName: row['author_name'] as String?,
      kind: row['kind'] as String,
      targetType: CommentTarget.fromString(row['target_type'] as String),
      targetId: row['target_id'].toString(),
      createdAt: row['created_at'] as DateTime,
    );
  }

  factory fromJson(Map json) {
    return Reaction(
      id: json['id'] as String,
      authorId: json['authorId'] as String,
      authorName: json['authorName'] as String?,
      kind: json['kind'] as String,
      targetType: CommentTarget.fromString(json['targetType'] as String),
      targetId: json['targetId'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

class const _Reaction({
  @override required final String id,
  @override required final String authorId,
  @override final String? authorName,
  @override required final String kind,
  @override required final ReactionTarget targetType,
  @override required final String targetId,
  @override required final DateTime createdAt,
}) implements Reaction {
  @override
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'authorId': authorId,
      'authorName': ?authorName,
      'kind': kind,
      'targetType': targetType.value,
      'targetId': targetId,
      'createdAt': createdAt.toUtc().toIso8601String(),
    };
  }
}

/// How many of each reaction a thing has, and which one, if any, the reader left.
typedef ReactionSummary = ({Map<String, int> counts, String? mine});

/// `GET /reactions/:targetType/:targetId` as the app reads it: a page of who
/// reacted, newest first, with the counts and the reader's own beside it. A
/// reaction this build can't read is left out of the page, and the counts keep
/// every word.
class Reactions implements Model {
  final List<Reaction> reactions;
  final Map<String, int> counts;
  final String? mine;
  final String? cursor;

  const new({required this.reactions, required this.counts, this.mine, this.cursor});

  factory fromJson(Map json) {
    return Reactions(
      reactions: readIndexed(json['reactions'], Reaction.fromJson).items,
      counts: {
        for (final MapEntry(:key, :value) in ((json['counts'] as Map?) ?? const {}).entries)
          if (value is int) '$key': value,
      },
      mine: json['mine'] as String?,
      cursor: json['cursor'] as String?,
    );
  }

  @override
  Map<String, dynamic> toMap() {
    return {
      'reactions': [for (final reaction in reactions) reaction.toMap()],
      'counts': counts,
      'mine': ?mine,
      'cursor': ?cursor,
    };
  }
}
