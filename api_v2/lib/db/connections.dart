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
    required String initiatorId,
    required String targetId,
    required ConnectionRole role,
    required ConnectionDomain domain,
  }) async {
    final result = await _pool.execute(
      _getConnection.toSql(),
      parameters: {'userId': initiatorId, 'targetId': targetId, 'role': role.value, 'domain': domain.value},
    );
    if (result.isEmpty) return null;
    return Connection.fromRow(result.first.toColumnMap());
  }

  @override
  Future<void> deleteConnection({
    required String initiatorId,
    required String targetId,
    required ConnectionRole role,
    required ConnectionDomain domain,
  }) {
    return _pool.execute(
      _deleteConnection.toSql(),
      parameters: {'initiatorId': initiatorId, 'targetId': targetId, 'domain': domain.value},
    );
  }

  @override
  Future<Connection> changeConnectionStatus({
    required String initiatorId,
    required String targetId,
    required ConnectionRole role,
    required ConnectionDomain domain,
    required ConnectionStatus newStatus,
  }) async {
    final existing = await getConnection(
      initiatorId: initiatorId,
      targetId: targetId,
      role: role,
      domain: domain,
    );

    if (existing == null) throw StateError('No connection between these users');
    if (!existing.status.canTransitionTo(newStatus)) {
      throw StateError('Cannot transition from ${existing.status.name} to ${newStatus.name}');
    }

    await _pool.execute(
      _updateConnectionStatus.toSql(),
      parameters: {
        'initiatorId': initiatorId,
        'targetId': targetId,
        'domain': domain.value,
        'newStatus': newStatus.name,
      },
    );

    return Connection(
      targetId: existing.targetId,
      role: existing.role,
      domain: existing.domain,
      status: newStatus,
      createdAt: existing.createdAt,
    );
  }

  @override
  Future<Iterable<Connection>?> queryConnections({required String initiatorId, required String targetId}) async {
    final response = await _client.query(
      tableName: table,
      indexName: 'connections_by_target_user_id',
      keyConditionExpression: '#PK = :PK AND #SK = :SK',
      expressionAttributeNames: {
        '#PK': 'PK',
        '#SK': 'target_id',
      },
      expressionAttributeValues: {
        ':PK': AttributeValue(s: connectionPk(initiatorId)),
        ':SK': AttributeValue(s: targetId),
      },
    );
    return response.items.map((item) => Connection.fromRow(item)).toList();
  }
}
