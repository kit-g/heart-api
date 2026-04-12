import 'package:heart_models/heart_models.dart';

enum ConnectionRole {
  coach,
  student,
  peer
  ;

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
  general
  ;

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
  paused
  ;

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
      createdAt: DateTime.parse(row['created_at'] as String),
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
}

class ConnectionListResponse implements Model {
  final List<Connection> connections;

  const ConnectionListResponse(this.connections);

  @override
  Map<String, dynamic> toMap() {
    return {
      'connections': connections.map((c) => c.toMap()).toList(),
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
}
