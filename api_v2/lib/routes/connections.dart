import 'package:heart/core/request.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/models/connections.dart';
import 'package:heart/models/errors.dart';
import 'package:heart_models/heart_models.dart';
import 'package:relic/relic.dart';

Future<ConnectionListResponse> getConnections(final Request request) async {
  final db = request.connectionsService;
  final roleQuery = request.url.queryParameters['role'];

  ConnectionRole? roleFilter;
  if (roleQuery != null && roleQuery.isNotEmpty) {
    roleFilter = ConnectionRole.fromString(roleQuery);
  }

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
      payload: {
        ...request.url.queryParameters,
        ...request.pathParameters.raw,
      },
    );
  }
}
