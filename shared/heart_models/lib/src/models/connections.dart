import 'package:heart_models/heart_models.dart';

import 'tolerant.dart' show readIndexed;

enum ConnectionRole {
  coach,
  student,
  peer;

  String get value => name.toUpperCase();

  /// Throws [ArgumentError] on an unknown role. It used to fall back to [peer],
  /// which meant a client asking to be someone's coach and typo'ing it got a
  /// peer connection and a 200. Mirrored by `connections_initiator_role_check`.
  factory fromString(String val) {
    return values.firstWhere(
      (e) => e.value == val.toUpperCase(),
      orElse: () => throw ArgumentError.value(val, 'role', 'unknown connection role'),
    );
  }

  ConnectionRole get reciprocal {
    return switch (this) {
      coach => student,
      student => coach,
      peer => peer,
    };
  }
}

enum ConnectionDomain {
  fitness,
  swimming,
  running,
  general;

  String get value => name.toLowerCase();

  /// Throws [ArgumentError] on an unknown domain, rather than quietly filing the
  /// request under [general]. Mirrored by `connections_domain_check`.
  factory fromString(String val) {
    return values.firstWhere(
      (e) => e.value == val.toLowerCase(),
      orElse: () => throw ArgumentError.value(val, 'domain', 'unknown connection domain'),
    );
  }
}

enum ConnectionStatus {
  pending,
  active,
  declined,
  severed,
  blocked,
  paused;

  /// Throws [ArgumentError] on an unknown status. Falling back to [pending] was
  /// how a nonsense `PUT` body turned into a silent no-op-looking 200. Mirrored
  /// by `connections_status_check`.
  factory fromString(String val) {
    return values.firstWhere(
      (e) => e.name == val.toLowerCase(),
      orElse: () => throw ArgumentError.value(val, 'status', 'unknown connection status'),
    );
  }

  /// Accepting or declining belongs to the person who *received* the request —
  /// never its author. Every other transition is either party's to make, subject
  /// to [ConnectionStatus.blocked]'s own rule (only the blocker lifts a block).
  bool get isTheTargetsAlone => this == active || this == declined;

  bool canTransitionTo(ConnectionStatus next) {
    if (this == next) return false;

    return switch (this) {
      pending => next == active || next == declined || next == blocked,
      active => next == paused || next == severed || next == blocked,
      paused => next == active || next == severed || next == blocked,
      declined => next == pending || next == blocked,
      severed => next == pending || next == blocked,
      blocked => next == severed,
    };
  }
}

/// What a student can open to their coach beyond the default, sent in a
/// connection's `shares`.
enum ConnectionShare {
  /// Workouts from before the connection was accepted.
  history,

  /// The student's goals.
  goals,

  /// What the coach reads, to the coach's assistant too.
  assistant;

  /// Throws [ArgumentError] on an unknown value. The server's own check: a
  /// connection read from the wire carries `shares` as plain strings, so a value
  /// a newer server added passes through a build that doesn't know it.
  factory fromString(String val) {
    return values.firstWhere(
      (e) => e.name == val,
      orElse: () => throw ArgumentError.value(val, 'shares', 'unknown share'),
    );
  }
}

abstract interface class Connection implements Model {
  /// Viewer-relative: the same relationship has a different one from each side.
  /// It identifies nothing, and no longer reaches the wire: [connectionId] is
  /// what every route takes.
  @Deprecated('Use connectionId, which every route takes')
  String get id;

  /// The relationship's identity, the same from both sides.
  String? get connectionId;

  /// When the relationship last became active from a request.
  DateTime? get acceptedAt;

  /// What the student opened to their coach, by [ConnectionShare] name.
  List<String> get shares;

  String get targetId;

  /// What the other person goes by in Heart now, as their profile says. Answered
  /// on reads (`GET /connections`, and one by its id); absent elsewhere, and when
  /// they have none or blocked the reader.
  String? get name;

  /// The other person's photo, on the same terms as [name].
  String? get avatar;

  ConnectionRole get role;

  ConnectionDomain get domain;

  ConnectionStatus get status;

  DateTime get createdAt;

  factory({
    required String targetId,
    required ConnectionRole role,
    required ConnectionDomain domain,
    required ConnectionStatus status,
    required DateTime createdAt,
    String? connectionId,
    DateTime? acceptedAt,
    List<String> shares,
    String? name,
    String? avatar,
  }) = _Connection.new;

  factory fromRow(Map<String, dynamic> row) {
    return Connection(
      targetId: row['target_id'] as String,
      role: ConnectionRole.fromString(row['role'] as String),
      domain: ConnectionDomain.fromString(row['domain'] as String),
      status: ConnectionStatus.fromString(row['status'] as String),
      createdAt: switch (row['created_at']) {
        DateTime dt => dt,
        String s => DateTime.parse(s),
        _ => DateTime.now(),
      },
      connectionId: row['connection_id']?.toString(),
      acceptedAt: row['accepted_at'] as DateTime?,
      shares: switch (row['shares']) {
        final List shares => [for (final share in shares) '$share'],
        _ => const [],
      },
      name: row['username'] as String?,
      avatar: row['avatar_url'] as String?,
    );
  }

  /// [role], [domain] and [status] are typed, so one this build doesn't know
  /// throws [ArgumentError]: read a list of them with [readEach]. [shares] are
  /// plain strings and carry any word.
  factory fromJson(Map json) {
    return Connection(
      targetId: json['targetId'] as String,
      role: ConnectionRole.fromString(json['role'] as String),
      domain: ConnectionDomain.fromString(json['domain'] as String),
      status: ConnectionStatus.fromString(json['status'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
      connectionId: json['connectionId'] as String?,
      acceptedAt: switch (json['acceptedAt']) {
        final String at => DateTime.parse(at),
        _ => null,
      },
      shares: switch (json['shares']) {
        final List shares => [for (final share in shares) '$share'],
        _ => const [],
      },
      name: json['name'] as String?,
      avatar: json['avatar'] as String?,
    );
  }

  @Deprecated('Routes take connectionId')
  static (String, ConnectionRole, ConnectionDomain) fromId(String id) {
    return switch (id.split('|')) {
      [String id, String role, String domain] => (
        id,
        ConnectionRole.fromString(role),
        ConnectionDomain.fromString(domain),
      ),
      _ => throw ArgumentError('Invalid connection ID format'),
    };
  }

  bool allows(String targetUserId);
}

class _Connection implements Connection {
  @override
  final String targetId;
  @override
  final ConnectionRole role;
  @override
  final ConnectionDomain domain;
  @override
  final ConnectionStatus status;
  @override
  final DateTime createdAt;
  @override
  final String? connectionId;
  @override
  final DateTime? acceptedAt;
  @override
  final List<String> shares;
  @override
  final String? name;
  @override
  final String? avatar;

  const new({
    required this.targetId,
    required this.role,
    required this.domain,
    required this.status,
    required this.createdAt,
    this.connectionId,
    this.acceptedAt,
    this.shares = const [],
    this.name,
    this.avatar,
  });

  @override
  String get id => '$targetId|${role.value}|${domain.value.toUpperCase()}';

  /// [role] and [domain] go out in lower case, as every newer answer's words do;
  /// [ConnectionRole.fromString] and [ConnectionDomain.fromString] read either.
  @override
  Map<String, dynamic> toMap() {
    return {
      'targetId': targetId,
      'role': role.name,
      'domain': domain.name,
      'status': status.name,
      'createdAt': createdAt.toIso8601String(),
      'connectionId': ?connectionId,
      'acceptedAt': ?acceptedAt?.toIso8601String(),
      'shares': shares,
      'name': ?name,
      'avatar': ?avatar,
    };
  }

  @override
  bool allows(String targetUserId) {
    if (targetUserId != targetId) return false;
    return role == .coach || role == .peer;
  }
}

class ConnectionListResponse with Iterable<Connection> implements Model {
  final List<Connection> connections;

  const new(this.connections);

  /// A connection this build can't read, such as one in a status it doesn't
  /// know, is left out.
  factory fromJson(Map json) {
    return ConnectionListResponse(readIndexed(json['connections'], Connection.fromJson).items);
  }

  @override
  Iterator<Connection> get iterator => connections.iterator;

  @override
  Map<String, dynamic> toMap() {
    return {
      'connections': map((c) => c.toMap()).toList(),
    };
  }
}

/// Reads and writes over the connection graph.
///
/// Note the two different ids. [createConnection] takes an `initiatorId` because
/// creating a connection is what makes you its initiator. Everything else takes
/// an **`actorId`** — the authenticated caller, who may be on either side of the
/// row — because a connection is a single row read and written from both ends,
/// and several rules turn on *which* end is asking.
abstract interface class ConnectionsService {
  Future<Connection> createConnection({
    required String initiatorId,
    required String targetId,
    required ConnectionRole role,
    required ConnectionDomain domain,
  });

  /// Ends the relationship from either side, keeping the row as `severed`. Throws
  /// if [actorId] is the party a standing block is against — otherwise blocking
  /// someone would be undone by the person blocked.
  Future<void> deleteConnection({
    required String actorId,
    required String targetId,
    required ConnectionRole role,
    required ConnectionDomain domain,
  });

  Future<Iterable<Connection>> getConnections(String userId, {ConnectionRole? roleFilter});

  /// Throws if the transition is illegal for the current status, or legal but
  /// not [actorId]'s to make — accepting and declining belong to the person who
  /// received the request, and only the blocker lifts a block.
  Future<Connection> changeConnectionStatus({
    required String actorId,
    required String targetId,
    required ConnectionRole role,
    required ConnectionDomain domain,
    required ConnectionStatus newStatus,
  });

  Future<Connection?> getConnection({
    required String actorId,
    required String targetId,
    required ConnectionRole role,
    required ConnectionDomain domain,
  });

  /// The connection [connectionId] as [actorId] sees it. Null if there is none, or
  /// [actorId] isn't on it.
  Future<Connection?> getConnectionById({required String actorId, required String connectionId});

  /// What the student of a coach connection has opened to their coach. Throws if
  /// [actorId] isn't that student.
  Future<Connection> changeConnectionShares({
    required String actorId,
    required String targetId,
    required ConnectionRole role,
    required ConnectionDomain domain,
    required Set<ConnectionShare> shares,
  });

  /// True if there is any active connection between the two users in any
  /// direction or domain, and no block stands between them.
  Future<bool> areConnected({required String userA, required String userB});
}
