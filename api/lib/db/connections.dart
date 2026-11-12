part of 'db.dart';

const _onlyTheStudentShares = 'Only the student of a live coaching connection chooses what it shares.';

mixin _Connections on _DatabaseBase implements ConnectionsService {
  @override
  Future<Connection> createConnection({
    required String initiatorId,
    required String targetId,
    required ConnectionRole role,
    required ConnectionDomain domain,
  }) async {
    Future<Result> create() => _pool.execute(
      _createConnection.toSql(),
      parameters: {
        'initiatorId': initiatorId,
        'targetId': targetId,
        'initiatorRole': role.value,
        'targetRole': role.reciprocal.value,
        'domain': domain.value,
      },
    );

    // Empty is also the other person asking at the same moment: the insert waited
    // for theirs and stood down, and the read can't see a row committed after the
    // statement began. A second run sees it.
    final result = switch (await create()) {
      final Result rows when rows.isEmpty => await create(),
      final rows => rows,
    };
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
  Future<Connection?> getConnectionById({required String actorId, required String connectionId}) async {
    final result = await _pool.execute(
      _getConnectionById.toSql(),
      parameters: {'userId': actorId, 'connectionId': connectionId},
    );
    return switch (result.firstOrNull?.toColumnMap()) {
      null => null,
      final row => Connection.fromRow(row),
    };
  }

  @override
  Future<void> deleteConnection({
    required String actorId,
    required String targetId,
    required ConnectionRole role,
    required ConnectionDomain domain,
  }) async {
    // A connection the other person blocked reads as ended to the one blocked, and
    // the statement leaves it as it is: ending it again changes nothing, as it
    // would if it had ended.
    await _pool.execute(
      _endConnection.toSql(),
      parameters: {'actorId': actorId, 'targetId': targetId, 'domain': domain.value},
    );
  }

  @override
  Future<Connection> changeConnectionStatus({
    required String actorId,
    required String targetId,
    required ConnectionRole role,
    required ConnectionDomain domain,
    required ConnectionStatus newStatus,
  }) async {
    final rows = await _pool.execute(
      _getConnection.toSql(),
      parameters: {'userId': actorId, 'targetId': targetId, 'role': role.value, 'domain': domain.value},
    );
    final row = rows.firstOrNull?.toColumnMap();
    if (row == null) throw StateError('No connection between these users');
    final existing = Connection.fromRow(row);
    // The one blocked can't tell: to them it's an ended connection, and acting on
    // it fails as it would with someone who isn't there.
    if (existing.status == .blocked && row['status_by'] == targetId) {
      throw NotFound(type: 'Connection', id: existing.connectionId ?? targetId);
    }
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
      throw Forbidden(reason: _refusal(existing, newStatus));
    }

    return Connection.fromRow(updated.first.toColumnMap());
  }

  @override
  Future<Connection> changeConnectionShares({
    required String actorId,
    required String targetId,
    required ConnectionRole role,
    required ConnectionDomain domain,
    required Set<ConnectionShare> shares,
  }) async {
    if (role != .student) throw const Forbidden(reason: _onlyTheStudentShares);
    final updated = await _pool.execute(
      _updateConnectionShares.toSql(),
      parameters: {
        'actorId': actorId,
        'targetId': targetId,
        'domain': domain.value,
        'shares': [for (final share in shares) share.name],
      },
    );
    if (updated.isEmpty) {
      throw const Forbidden(reason: _onlyTheStudentShares);
    }
    return Connection.fromRow(updated.first.toColumnMap());
  }

  /// The UPDATE matched nothing. The legality and existence checks already
  /// passed, so it is one of the actor rules — or, rarely, someone else moved
  /// the status between the read and the write.
  static String _refusal(Connection existing, ConnectionStatus to) {
    final from = existing.status;
    final coaching = existing.role != .peer;
    if (coaching && (to == .pending || (from == .pending && to == .active))) {
      return 'A coaching connection starts with an invitation.';
    }
    if (coaching && from == .paused && to == .active) {
      return 'Only the student can resume a paused coaching connection.';
    }
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
