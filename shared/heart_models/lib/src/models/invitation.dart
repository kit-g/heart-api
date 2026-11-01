import 'coach_program.dart';
import 'connections.dart';
import 'misc.dart';

/// A link one person makes to start a relationship, as its inviter sees it.
abstract interface class Invitation implements Model {
  String get id;

  /// The name the inviter wrote for the person it is for.
  String get name;

  /// `pending`, `accepted`, `declined`, `expired` or `canceled`, and a later
  /// server may add a word. Plain text, so a build that doesn't know one keeps it.
  String get status;

  String get role;

  String get domain;

  DateTime get expiresAt;

  DateTime get createdAt;

  /// The link's secret, only when it was just made or renewed.
  String? get token;

  factory({
    required String id,
    required String name,
    required String status,
    required String role,
    required String domain,
    required DateTime expiresAt,
    required DateTime createdAt,
    String? token,
  }) = _Invitation.new;

  factory fromRow(Map row, {String? token}) {
    return Invitation(
      id: row['id'].toString(),
      name: row['name'] as String,
      status: row['status'] as String,
      role: row['role'] as String,
      domain: row['domain'] as String,
      expiresAt: row['expires_at'] as DateTime,
      createdAt: row['created_at'] as DateTime,
      token: token,
    );
  }

  factory fromJson(Map json) {
    return Invitation(
      id: json['id'] as String,
      name: json['name'] as String,
      status: json['status'] as String,
      role: json['role'] as String,
      domain: json['domain'] as String,
      expiresAt: DateTime.parse(json['expiresAt'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
      token: json['token'] as String?,
    );
  }
}

class _Invitation implements Invitation {
  @override
  final String id;
  @override
  final String name;
  @override
  final String status;
  @override
  final String role;
  @override
  final String domain;
  @override
  final DateTime expiresAt;
  @override
  final DateTime createdAt;
  @override
  final String? token;

  const new({
    required this.id,
    required this.name,
    required this.status,
    required this.role,
    required this.domain,
    required this.expiresAt,
    required this.createdAt,
    this.token,
  });

  @override
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'status': status,
      'role': role,
      'domain': domain,
      'expiresAt': expiresAt.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'token': ?token,
    };
  }
}

/// The answer to accepting: the relationship, and how the program it named went.
class AcceptedInvitation implements Model {
  final Connection connection;

  /// Null when the invitation named no program.
  final ProgramDelivery? delivery;

  const new(this.connection, {this.delivery});

  @override
  Map<String, dynamic> toMap() {
    return {...connection.toMap(), 'programDelivered': ?delivery?.delivered, 'programId': ?delivery?.programId};
  }
}

/// What someone who opens a link, signed in or not, can read: who is asking, and
/// whether the link is good. Nothing else about anyone.
abstract interface class InvitationPreview implements Model {
  String? get inviterName;

  String? get inviterAvatar;

  bool get good;

  factory({String? inviterName, String? inviterAvatar, required bool good}) = _InvitationPreview.new;

  factory fromJson(Map json) {
    return InvitationPreview(
      inviterName: json['inviterName'] as String?,
      inviterAvatar: json['inviterAvatar'] as String?,
      good: json['good'] as bool,
    );
  }
}

class _InvitationPreview implements InvitationPreview {
  @override
  final String? inviterName;
  @override
  final String? inviterAvatar;
  @override
  final bool good;

  const new({this.inviterName, this.inviterAvatar, required this.good});

  @override
  Map<String, dynamic> toMap() {
    return {'inviterName': ?inviterName, 'inviterAvatar': ?inviterAvatar, 'good': good};
  }
}

/// Someone the caller has blocked.
abstract interface class BlockedPerson implements Model {
  String get id;

  String? get name;

  String? get avatar;

  DateTime get since;

  factory({required String id, String? name, String? avatar, required DateTime since}) = _BlockedPerson.new;

  factory fromRow(Map row) {
    return BlockedPerson(
      id: row['blocked_id'] as String,
      name: row['username'] as String?,
      avatar: row['avatar_url'] as String?,
      since: row['created_at'] as DateTime,
    );
  }
}

class _BlockedPerson implements BlockedPerson {
  @override
  final String id;
  @override
  final String? name;
  @override
  final String? avatar;
  @override
  final DateTime since;

  const new({required this.id, this.name, this.avatar, required this.since});

  @override
  Map<String, dynamic> toMap() {
    return {'id': id, 'name': ?name, 'avatar': ?avatar, 'since': since.toIso8601String()};
  }
}
