part of 'db.dart';

mixin _Connections on _DatabaseBase implements ConnectionsService {
  @override
  Future<Connection> createConnection({
    required String initiatorId,
    required String targetId,
    required ConnectionRole role,
    required ConnectionDomain domain,
  }) async {
    final result = await _pool.execute(
      _createConnection.toSql(),
      parameters: {
        'initiatorId': initiatorId,
        'targetId': targetId,
        'initiatorRole': role.value,
        'targetRole': role.reciprocal.value,
        'domain': domain.value,
      },
    );

    if (result.isEmpty) throw NotFound(type: 'User', id: targetId);
    return Connection.fromRow(result.first.toColumnMap());
  }

  @override
  Future<Iterable<Connection>> getConnections(String userId, {ConnectionRole? roleFilter}) async {
    final result = await _pool.execute(
      _listConnections.toSql(),
      parameters: {'userId': userId, 'role': roleFilter?.value},
    );
    return result.map((row) => Connection.fromRow(row.toColumnMap()));
  }

  @override
  Future<Connection?> getConnection({
    required String actorId,
    required String targetId,
    required ConnectionRole role,
    required ConnectionDomain domain,
  }) async {
    final result = await _pool.execute(
      _getConnection.toSql(),
      parameters: {'userId': actorId, 'targetId': targetId, 'role': role.value, 'domain': domain.value},
    );
    if (result.isEmpty) return null;
    return Connection.fromRow(result.first.toColumnMap());
  }

  @override
  Future<void> deleteConnection({
    required String actorId,
    required String targetId,
    required ConnectionRole role,
    required ConnectionDomain domain,
  }) async {
    final result = await _pool.execute(
      _deleteConnection.toSql(),
      parameters: {'actorId': actorId, 'targetId': targetId, 'domain': domain.value},
    );

    final row = result.first.toColumnMap();
    // Nothing there is a no-op, as it always has been. Something there that did
    // not go is the block guard refusing.
    if (row['existed'] == true && row['deleted'] != true) {
      throw const Forbidden(reason: 'You cannot remove a connection that blocks you.');
    }
  }

  @override
  Future<Connection> changeConnectionStatus({
    required String actorId,
    required String targetId,
    required ConnectionRole role,
    required ConnectionDomain domain,
    required ConnectionStatus newStatus,
  }) async {
    final existing = await getConnection(
      actorId: actorId,
      targetId: targetId,
      role: role,
      domain: domain,
    );

    if (existing == null) throw StateError('No connection between these users');
    if (!existing.status.canTransitionTo(newStatus)) {
      throw StateError('Cannot transition from ${existing.status.name} to ${newStatus.name}');
    }

    // The transition is legal in the abstract; whether it is *this* caller's to
    // make, and whether the status is still what we just read, are settled by
    // the UPDATE's own WHERE so neither can be raced past.
    final updated = await _pool.execute(
      _updateConnectionStatus.toSql(),
      parameters: {
        'actorId': actorId,
        'targetId': targetId,
        'domain': domain.value,
        'newStatus': newStatus.name,
        'expectedStatus': existing.status.name,
      },
    );

    if (updated.isEmpty) {
      throw Forbidden(reason: _refusal(existing.status, newStatus));
    }

    return Connection(
      targetId: existing.targetId,
      role: existing.role,
      domain: existing.domain,
      status: newStatus,
      createdAt: existing.createdAt,
    );
  }

  /// The UPDATE matched nothing. The legality and existence checks already
  /// passed, so it is one of the actor rules — or, rarely, someone else moved
  /// the status between the read and the write.
  static String _refusal(ConnectionStatus from, ConnectionStatus to) {
    if (from == .pending && to.isTheTargetsAlone) {
      return 'Only the person you sent this request to can ${to == ConnectionStatus.active ? 'accept' : 'decline'} it.';
    }
    if (from == .blocked) {
      return 'Only the person who blocked can lift a block.';
    }
    return 'This connection changed while you were acting on it. Fetch it again.';
  }

  @override
  Future<bool> areConnected({required String userA, required String userB}) async {
    final result = await _pool.execute(
      _areConnected.toSql(),
      parameters: {'userA': userA, 'userB': userB},
    );
    return result.isNotEmpty;
  }
}
