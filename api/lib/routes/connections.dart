import 'package:heart/core/request.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/inputs/inputs.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/models/errors.dart';
import 'package:heart_models/heart_models.dart';
import 'package:relic/relic.dart';

Future<ConnectionListResponse> getConnections(Request request) async {
  final query = ConnectionListQuery.fromRequest(request);
  final connections = await request.connectionsService.getConnections(
    request.userId,
    roleFilter: query.role,
  );
  return ConnectionListResponse(connections.toList());
}

Future<Connection> createConnection(Request request) async {
  final input = await ConnectionCreateIn.fromRequest(request);
  return request.connectionsService.createConnection(
    initiatorId: request.userId,
    targetId: input.targetId,
    role: input.role,
    domain: input.domain,
  );
}

/// The caller's side of the connection in the path. One they aren't on answers
/// like one that isn't there.
Future<Connection> _connectionInPath(Request request) async {
  final connectionId = request.connectionIdInPath;
  final connection = await request.connectionsService.getConnectionById(
    actorId: request.userId,
    connectionId: connectionId,
  );
  return connection ?? (throw NotFound(type: 'Connection', id: connectionId));
}

Future<Model?> deleteConnection(Request request) async {
  final connection = await _connectionInPath(request);
  await request.connectionsService.deleteConnection(
    actorId: request.userId,
    targetId: connection.targetId,
    role: connection.role,
    domain: connection.domain,
  );
  throw const NoContent();
}

Future<Connection> changeConnectionShares(Request request) async {
  final input = await ConnectionSharesIn.fromRequest(request);
  final connection = await _connectionInPath(request);
  return request.connectionsService.changeConnectionShares(
    actorId: request.userId,
    targetId: connection.targetId,
    role: connection.role,
    domain: connection.domain,
    shares: input.shares,
  );
}

Future<Connection?> reactToConnection(Request request) async {
  final input = await ConnectionStatusIn.fromRequest(request);
  final connection = await _connectionInPath(request);
  try {
    return await request.connectionsService.changeConnectionStatus(
      actorId: request.userId,
      targetId: connection.targetId,
      role: connection.role,
      domain: connection.domain,
      newStatus: input.status,
    );
  } on StateError catch (e) {
    // A transition the state machine forbids outright, or the row gone since.
    throw BadRequest(reason: e.message.toString(), payload: request.signature());
  }
}
