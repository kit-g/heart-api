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

    if (result.isEmpty) {
      throw NotFound(type: 'User', id: targetId);
    }

    return Connection.fromRow(result.first.toColumnMap());
  }

  @override
  Future<Iterable<Connection>> getConnections(String userId, {ConnectionRole? roleFilter}) async {
    final prefix = roleFilter != null ? '$_connectionSk${roleFilter.value}#' : _connectionSk;

    final response = await _client.query(
      tableName: table,
      keyConditionExpression: '#PK = :PK AND begins_with(#SK, :prefix)',
      expressionAttributeNames: {
        '#PK': 'PK',
        '#SK': 'SK',
      },
      expressionAttributeValues: {
        ':PK': AttributeValue(s: connectionPk(userId)),
        ':prefix': AttributeValue(s: prefix),
      },
    );

    return response.items.map(Connection.fromRow);
  }

  @override
  Future<void> deleteConnection({
    required String initiatorId,
    required String targetId,
    required ConnectionRole role,
    required ConnectionDomain domain,
  }) async {
    final reciprocalRole = role.reciprocal;

    try {
      await _client.transactWrite(
        transactItems: [
          TransactWrite(
            delete: Operation(
              tableName: table,
              expression: 'attribute_exists(PK)',
              value: {
                'PK': AttributeValue(s: connectionPk(initiatorId)),
                'SK': AttributeValue(s: connectionSk(role, domain, targetId)),
              },
            ),
          ),
          TransactWrite(
            delete: Operation(
              tableName: table,
              expression: 'attribute_exists(PK)',
              value: {
                'PK': AttributeValue(s: connectionPk(targetId)),
                'SK': AttributeValue(s: connectionSk(reciprocalRole, domain, initiatorId)),
              },
            ),
          ),
        ],
      );
    } on TransactionCanceledException catch (e) {
      if (e.message case String message when !message.contains('ConditionalCheckFailed')) {
        rethrow;
      }
    }
  }

  @override
  Future<Connection?> getConnection({
    required String initiatorId,
    required String targetId,
    required ConnectionRole role,
    required ConnectionDomain domain,
  }) async {
    final response = await _client.get(
      tableName: table,
      key: {
        'PK': AttributeValue(s: connectionPk(initiatorId)),
        'SK': AttributeValue(s: connectionSk(role, domain, targetId)),
      },
    );

    try {
      return Connection.fromRow(response.item);
    } on TypeError {
      return null;
    }
  }

  @override
  Future<Connection> changeConnectionStatus({
    required String initiatorId,
    required String targetId,
    required ConnectionRole role,
    required ConnectionDomain domain,
    required ConnectionStatus newStatus,
  }) async {
    final reciprocalRole = role.reciprocal;

    final existing = await getConnection(
      initiatorId: initiatorId,
      targetId: targetId,
      role: role,
      domain: domain,
    );

    if (existing == null) {
      throw StateError('No connection between these users');
    }

    if (!existing.status.canTransitionTo(newStatus)) {
      throw StateError('Cannot transition connection from ${existing.status.name} to ${newStatus.name}');
    }

    await _client.transactWrite(
      transactItems: [
        TransactWrite(
          update: UpdateOperation(
            tableName: table,
            expression: 'attribute_exists(PK)',
            value: {
              'PK': AttributeValue(s: connectionPk(initiatorId)),
              'SK': AttributeValue(s: connectionSk(role, domain, targetId)),
            },
            updateExpression: 'SET #status = :newStatus',
            expressionAttributeNames: {
              '#status': 'status',
            },
            expressionAttributeValues: {
              ':newStatus': AttributeValue(s: newStatus.name),
            },
          ),
        ),
        TransactWrite(
          update: UpdateOperation(
            tableName: table,
            expression: 'attribute_exists(PK)',
            value: {
              'PK': AttributeValue(s: connectionPk(targetId)),
              'SK': AttributeValue(s: connectionSk(reciprocalRole, domain, initiatorId)),
            },
            updateExpression: 'SET #status = :newStatus',
            expressionAttributeNames: {
              '#status': 'status',
            },
            expressionAttributeValues: {
              ':newStatus': AttributeValue(s: newStatus.name),
            },
          ),
        ),
      ],
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
