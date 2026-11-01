import 'misc.dart';

/// A conversation in someone's inbox.
abstract interface class Thread implements Model {
  String get id;

  String? get connectionId;

  /// The other person; null once their account is gone.
  String? get otherId;

  String? get otherName;

  String? get otherAvatar;

  /// From the other person, after this person's read position.
  int get unread;

  DateTime? get lastAt;

  /// When either person last deleted the conversation for both. A device holding
  /// anything older drops it.
  DateTime? get clearedAt;

  String? get clearedBy;

  factory({
    required String id,
    String? connectionId,
    String? otherId,
    String? otherName,
    String? otherAvatar,
    int unread,
    DateTime? lastAt,
    DateTime? clearedAt,
    String? clearedBy,
  }) = _Thread.new;

  factory fromRow(Map row) {
    return Thread(
      id: row['id'].toString(),
      connectionId: row['connection_id']?.toString(),
      otherId: row['other_id'] as String?,
      otherName: row['other_name'] as String?,
      otherAvatar: row['other_avatar'] as String?,
      unread: (row['unread'] as num?)?.toInt() ?? 0,
      lastAt: row['last_at'] as DateTime?,
      clearedAt: row['cleared_at'] as DateTime?,
      clearedBy: row['cleared_by'] as String?,
    );
  }
}

class _Thread implements Thread {
  @override
  final String id;
  @override
  final String? connectionId;
  @override
  final String? otherId;
  @override
  final String? otherName;
  @override
  final String? otherAvatar;
  @override
  final int unread;
  @override
  final DateTime? lastAt;
  @override
  final DateTime? clearedAt;
  @override
  final String? clearedBy;

  const new({
    required this.id,
    this.connectionId,
    this.otherId,
    this.otherName,
    this.otherAvatar,
    this.unread = 0,
    this.lastAt,
    this.clearedAt,
    this.clearedBy,
  });

  @override
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'connectionId': ?connectionId,
      'otherId': ?otherId,
      'otherName': ?otherName,
      'otherAvatar': ?otherAvatar,
      'unread': unread,
      'lastAt': ?lastAt?.toIso8601String(),
      'clearedAt': ?clearedAt?.toIso8601String(),
      'clearedBy': ?clearedBy,
    };
  }
}

/// What was said in a thread: ciphertext and what a report later needs to check it.
abstract interface class ThreadItem implements Model {
  String get id;

  String get threadId;

  String? get senderId;

  String get kind;

  /// What it's about, such as `exercise_set`, and which one.
  String? get subjectType;

  String? get subjectId;

  String get content;

  String get commitment;

  String get tag;

  String get tagKey;

  /// When the device says it was written. What to show.
  DateTime get at;

  /// When it arrived, as [tag] states it.
  DateTime get createdAt;

  /// Its place in the stored order, opaque. What a read position and a page take.
  String? get cursor;

  factory({
    required String id,
    required String threadId,
    String? senderId,
    required String kind,
    String? subjectType,
    String? subjectId,
    required String content,
    required String commitment,
    required String tag,
    required String tagKey,
    required DateTime at,
    required DateTime createdAt,
    String? cursor,
  }) = _ThreadItem.new;

  factory fromRow(Map row, {String? cursor}) {
    return ThreadItem(
      id: row['id'].toString(),
      threadId: row['thread_id'].toString(),
      senderId: row['sender_id'] as String?,
      kind: row['kind'] as String,
      subjectType: row['subject_type'] as String?,
      subjectId: row['subject_id'] as String?,
      content: row['content'] as String,
      commitment: row['commitment'] as String,
      tag: row['tag'] as String,
      tagKey: row['tag_key'] as String,
      at: row['at'] as DateTime,
      createdAt: row['created_at'] as DateTime,
      cursor: cursor,
    );
  }

  factory fromJson(Map json) {
    return ThreadItem(
      id: json['id'] as String,
      threadId: json['threadId'] as String,
      senderId: json['senderId'] as String?,
      kind: json['kind'] as String,
      subjectType: json['subjectType'] as String?,
      subjectId: json['subjectId'] as String?,
      content: json['content'] as String,
      commitment: json['commitment'] as String,
      tag: json['tag'] as String,
      tagKey: json['tagKey'] as String,
      at: DateTime.parse(json['at'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
      cursor: json['cursor'] as String?,
    );
  }
}

class _ThreadItem implements ThreadItem {
  @override
  final String id;
  @override
  final String threadId;
  @override
  final String? senderId;
  @override
  final String kind;
  @override
  final String? subjectType;
  @override
  final String? subjectId;
  @override
  final String content;
  @override
  final String commitment;
  @override
  final String tag;
  @override
  final String tagKey;
  @override
  final DateTime at;
  @override
  final DateTime createdAt;
  @override
  final String? cursor;

  const new({
    required this.id,
    required this.threadId,
    this.senderId,
    required this.kind,
    this.subjectType,
    this.subjectId,
    required this.content,
    required this.commitment,
    required this.tag,
    required this.tagKey,
    required this.at,
    required this.createdAt,
    this.cursor,
  });

  @override
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'threadId': threadId,
      'senderId': ?senderId,
      'kind': kind,
      'subjectType': ?subjectType,
      'subjectId': ?subjectId,
      'content': content,
      'commitment': commitment,
      'tag': tag,
      'tagKey': tagKey,
      'at': at.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'cursor': ?cursor,
    };
  }
}

/// `GET /threads`: an inbox, with how much is unread across it.
class ThreadList implements Model {
  final List<Thread> threads;

  const new(this.threads);

  @override
  Map<String, dynamic> toMap() {
    return {
      'threads': [for (final thread in threads) thread.toMap()],
      'unread': threads.fold<int>(0, (sum, thread) => sum + thread.unread),
    };
  }
}

/// A coach's note on a client: ciphertext only that coach's devices can open.
abstract interface class CoachNote implements Model {
  String get id;

  String? get connectionId;

  String get content;

  DateTime get updatedAt;

  factory({required String id, String? connectionId, required String content, required DateTime updatedAt}) =
      _CoachNote.new;

  factory fromRow(Map row) {
    return CoachNote(
      id: row['id'].toString(),
      connectionId: row['connection_id']?.toString(),
      content: row['content'] as String,
      updatedAt: row['updated_at'] as DateTime,
    );
  }
}

class _CoachNote implements CoachNote {
  @override
  final String id;
  @override
  final String? connectionId;
  @override
  final String content;
  @override
  final DateTime updatedAt;

  const new({required this.id, this.connectionId, required this.content, required this.updatedAt});

  @override
  Map<String, dynamic> toMap() {
    return {'id': id, 'connectionId': ?connectionId, 'content': content, 'updatedAt': updatedAt.toIso8601String()};
  }
}
