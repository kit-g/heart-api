import 'package:heart_models/heart_models.dart';

enum ConnectionRole {
  coach,
  student,
  peer
  ;

  String get value => name.toUpperCase();

  static ConnectionRole fromString(String val) {
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

  static ConnectionDomain fromString(String val) {
    return values.firstWhere((e) => e.value == val.toLowerCase(), orElse: () => general);
  }
}

class Connection implements Model {
  final String targetId;
  final ConnectionRole role;
  final ConnectionDomain domain;
  final String status;
  final DateTime createdAt;

  const Connection({
    required this.targetId,
    required this.role,
    required this.domain,
    required this.status,
    required this.createdAt,
  });

  factory Connection.fromRow(Map<String, dynamic> row) {
    return Connection(
      targetId: row['targetId'] as String,
      role: ConnectionRole.fromString(row['role'] as String),
      domain: ConnectionDomain.fromString(row['domain'] as String),
      status: row['status'] as String,
      createdAt: DateTime.parse(row['createdAt'] as String),
    );
  }

  @override
  Map<String, dynamic> toMap() {
    return {
      'targetId': targetId,
      'role': role.value.toUpperCase(),
      'domain': domain.value.toUpperCase(),
      'status': status,
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
}
