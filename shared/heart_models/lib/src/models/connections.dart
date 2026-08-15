import 'package:heart_models/heart_models.dart';

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

abstract interface class Connection implements Model {
  String get id;

  String get targetId;

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
    );
  }

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

  const new({
    required this.targetId,
    required this.role,
    required this.domain,
    required this.status,
    required this.createdAt,
  });

  @override
  String get id => '$targetId|${role.value.toUpperCase()}|${domain.value.toUpperCase()}';

  @override
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'targetId': targetId,
      'role': role.value.toUpperCase(),
      'domain': domain.value.toUpperCase(),
      'status': status.name,
      'createdAt': createdAt.toIso8601String(),
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

  /// Hard-deletes the row from either side. Throws if [actorId] is the party a
  /// standing block is against — otherwise blocking someone would be undone by
  /// the person blocked.
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

  /// True if there is any active connection between the two users in any
  /// direction or domain. Used for permission checks (e.g. commenting).
  Future<bool> areConnected({required String userA, required String userB});
}
