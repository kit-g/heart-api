import 'package:heart/core/request.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/models/connections.dart';
import 'package:heart/models/errors.dart';
import 'package:heart_models/heart_models.dart';
import 'package:relic/relic.dart';

Future<ConnectionListResponse> getConnections(Request request) async {
  final db = request.connectionsService;
  final roleQuery = request.url.queryParameters['role'];

  ConnectionRole? roleFilter;
  if (roleQuery != null && roleQuery.isNotEmpty) {
    roleFilter = ConnectionRole.fromString(roleQuery);
  }

  final connections = await db.getConnections(request.userId, roleFilter: roleFilter);
  return ConnectionListResponse(connections.toList());
}

Future<Connection> createConnection(Request request) async {
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

Future<Model?> deleteConnection(Request request) async {
  final db = request.connectionsService;
  final targetId = request.pathParameters.raw[#targetId]!;

  final roleParam = request.url.queryParameters['role'];
  final domainParam = request.url.queryParameters['domain'];

  if (roleParam == null || domainParam == null) {
    throw BadRequest(
      reason: 'role and domain query parameters are required for deletion',
      payload: {
        ...request.url.queryParameters,
        ...request.pathParameters.raw,
      },
    );
  }

  final role = ConnectionRole.fromString(roleParam);
  final domain = ConnectionDomain.fromString(domainParam);

  await db.deleteConnection(
    initiatorId: request.userId,
    targetId: targetId,
    role: role,
    domain: domain,
  );

  throw const NoContent();
}
