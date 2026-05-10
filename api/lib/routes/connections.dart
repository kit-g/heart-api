import 'package:heart/core/request.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/models/errors.dart';
import 'package:heart_models/heart_models.dart';
import 'package:relic/relic.dart';

Future<ConnectionListResponse> getConnections(final Request request) async {
  final db = request.connectionsService;
  final roleFilter = switch (request.url.queryParameters['role']) {
    String s when s.isNotEmpty => ConnectionRole.fromString(s),
    _ => null,
  };

  final connections = await db.getConnections(request.userId, roleFilter: roleFilter);
  return ConnectionListResponse(connections.toList());
}

Future<Connection> createConnection(final Request request) async {
  final db = request.connectionsService;
  final body = await request.json();

  final targetId = body['targetId'] as String;
  final role = ConnectionRole.fromString(body['role'] as String);
  final domain = ConnectionDomain.fromString(body['domain'] as String);

  return db.createConnection(
    initiatorId: request.userId,
    targetId: targetId,
    role: role,
    domain: domain,
  );
}

Future<Model?> deleteConnection(final Request request) async {
  final db = request.connectionsService;
  final connectionId = request.pathParameters.raw[#connectionId]!;

  try {
    final (targetId, role, domain) = Connection.fromId(connectionId);

    await db.deleteConnection(
      initiatorId: request.userId,
      targetId: targetId,
      role: role,
      domain: domain,
    );

    throw const NoContent();
  } on ArgumentError catch (e) {
    throw BadRequest(
      reason: e.message.toString(),
      payload: request.signature(),
    );
  }
}

Future<Connection?> reactToConnection(final Request request) async {
  final db = request.connectionsService;
  final connectionId = request.pathParameters.raw[#connectionId]!;
  final body = await request.json();
  final status = body['status'] as String?;

  if (status == null) {
    throw BadRequest(
      reason: 'Status required',
      payload: {
        ...request.signature(),
        ...body,
      },
    );
  }

  try {
    final (targetId, role, domain) = Connection.fromId(connectionId);

    return await db.changeConnectionStatus(
      initiatorId: request.userId,
      targetId: targetId,
      role: role,
      domain: domain,
      newStatus: ConnectionStatus.fromString(status),
    );
  } on ArgumentError catch (e) {
    throw BadRequest(
      reason: e.message.toString(),
      payload: request.signature(),
    );
  } on StateError catch (e) {
    throw BadRequest(
      reason: e.message.toString(),
      payload: request.signature(),
    );
  }
}
