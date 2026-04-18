import '../models/connections.dart';

Future<bool> allowedByConnection({
  required ConnectionsService db,
  required String userId,
  required String targetUserId,
}) async {
  if (targetUserId == userId) return true;
  final connections = await db.queryConnections(
    initiatorId: userId,
    targetId: targetUserId,
  );

  return connections?.any((connection) => connection.allows(targetUserId)) ?? false;
}
