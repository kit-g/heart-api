import 'package:heart_models/heart_models.dart';

enum ConnectionRole {
  coach,
  student,
  peer;

  String get value => name.toUpperCase();

  factory ConnectionRole.fromString(String val) {
    return values.firstWhere((e) => e.value == val.toUpperCase(), orElse: () => peer);
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

  factory ConnectionDomain.fromString(String val) {
    return values.firstWhere((e) => e.value == val.toLowerCase(), orElse: () => general);
  }
}

enum ConnectionStatus {
  pending,
  active,
  declined,
  severed,
  blocked,
  paused;

  factory ConnectionStatus.fromString(String val) {
    return values.firstWhere((e) => e.name == val.toLowerCase(), orElse: () => pending);
  }

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

  factory Connection({
    required final String targetId,
    required final ConnectionRole role,
    required final ConnectionDomain domain,
    required final ConnectionStatus status,
    required final DateTime createdAt,
  }) = _Connection.new;

  factory Connection.fromRow(Map<String, dynamic> row) {
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

  const _Connection({
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

  const ConnectionListResponse(this.connections);

  @override
  Iterator<Connection> get iterator => connections.iterator;

  @override
  Map<String, dynamic> toMap() {
    return {
      'connections': map((c) => c.toMap()).toList(),
    };
  }
}

abstract interface class ConnectionsService {
  Future<Connection> createConnection({
    required String initiatorId,
    required String targetId,
    required ConnectionRole role,
    required ConnectionDomain domain,
  });

  Future<void> deleteConnection({
    required String initiatorId,
    required String targetId,
    required ConnectionRole role,
    required ConnectionDomain domain,
  });

  Future<Iterable<Connection>> getConnections(String userId, {ConnectionRole? roleFilter});

  Future<Connection> changeConnectionStatus({
    required String initiatorId,
    required String targetId,
    required ConnectionRole role,
    required ConnectionDomain domain,
    required ConnectionStatus newStatus,
  });

  Future<Connection?> getConnection({
    required String initiatorId,
    required String targetId,
    required ConnectionRole role,
    required ConnectionDomain domain,
  });

  /// True if there is any active connection between the two users in any
  /// direction or domain. Used for permission checks (e.g. commenting).
  Future<bool> areConnected({required String userA, required String userB});
}
