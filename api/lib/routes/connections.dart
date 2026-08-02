import 'package:heart/core/request.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/inputs/inputs.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/models/errors.dart';
import 'package:heart_models/heart_models.dart';
import 'package:relic/relic.dart';

Future<ConnectionListResponse> getConnections(final Request request) async {
  final query = ConnectionListQuery.fromRequest(request);
  final connections = await request.connectionsService.getConnections(
    request.userId,
    roleFilter: query.role,
  );
  return ConnectionListResponse(connections.toList());
}

Future<Connection> createConnection(final Request request) async {
  final input = await ConnectionCreateIn.fromRequest(request);
  return request.connectionsService.createConnection(
    initiatorId: request.userId,
    targetId: input.targetId,
    role: input.role,
    domain: input.domain,
  );
}

Future<Model?> deleteConnection(final Request request) {
  return deleteConnectionById(request, request.rawPathParameters[#connectionId]!);
}

Future<Model?> deleteConnectionById(final Request request, final String connectionId) async {
  final ref = ConnectionRef.parse(connectionId);

  await request.connectionsService.deleteConnection(
    actorId: request.userId,
    targetId: ref.targetId,
    role: ref.role,
    domain: ref.domain,
  );

  throw const NoContent();
}

Future<Connection?> reactToConnection(final Request request) {
  return reactToConnectionById(request, request.rawPathParameters[#connectionId]!);
}

Future<Connection?> reactToConnectionById(final Request request, final String connectionId) async {
  final ref = ConnectionRef.parse(connectionId);
  final input = await ConnectionStatusIn.fromRequest(request);

  try {
    return await request.connectionsService.changeConnectionStatus(
      actorId: request.userId,
      targetId: ref.targetId,
      role: ref.role,
      domain: ref.domain,
      newStatus: input.status,
    );
  } on StateError catch (e) {
    // No such connection, or a transition the state machine forbids outright.
    throw BadRequest(reason: e.message.toString(), payload: request.signature());
  }
}
