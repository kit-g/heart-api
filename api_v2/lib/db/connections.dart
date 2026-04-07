part of 'db.dart';

const _connectionPk = 'USER#';
const _connectionSk = 'CONN#';

mixin _Connections on _DatabaseBase implements ConnectionsService {
  String get table;

  static String connectionPk(String userId) => '$_connectionPk$userId';

  static String connectionSk(ConnectionRole role, ConnectionDomain domain, String targetId) {
    return '$_connectionSk${role.value.toUpperCase()}#${domain.value.toUpperCase()}#$targetId';
  }

  @override
  Future<Connection> createConnection({
    required String initiatorId,
    required String targetId,
    required ConnectionRole role,
    required ConnectionDomain domain,
  }) async {
    final reciprocalRole = role.reciprocal;
    final now = DateTime.now();
    final connection = Connection(
      targetId: targetId,
      role: role,
      domain: domain,
      status: 'active',
      createdAt: now,
    );

    try {
      await client.transactWrite(
        transactItems: [
          TransactWrite(
            put: Operation(
              tableName: table,
              expression: 'attribute_not_exists(PK)',
              value: {
                'PK': AttributeValue(s: connectionPk(initiatorId)),
                'SK': AttributeValue(s: connectionSk(role, domain, targetId)),
                'targetId': AttributeValue(s: targetId),
                'role': AttributeValue(s: role.value),
                'domain': AttributeValue(s: domain.value),
                'status': AttributeValue(s: connection.status),
                'createdAt': AttributeValue(s: now.toIso8601String()),
              },
            ),
          ),
          TransactWrite(
            put: Operation(
              tableName: table,
              expression: 'attribute_not_exists(PK)',
              value: {
                'PK': AttributeValue(s: connectionPk(targetId)),
                'SK': AttributeValue(s: connectionSk(reciprocalRole, domain, initiatorId)),
                'targetId': AttributeValue(s: targetId),
                'role': AttributeValue(s: reciprocalRole.value),
                'domain': AttributeValue(s: domain.value),
                'status': AttributeValue(s: connection.status),
                'createdAt': AttributeValue(s: now.toIso8601String()),
              },
            ),
          ),
        ],
      );
    } on TransactionCanceledException catch (e) {
      if (e.message case String message when !message.contains('ConditionalCheckFailed')) {
        rethrow;
      }

      // connection exists, query
      final response = await client.query(
        tableName: table,
        keyConditionExpression: '#PK = :PK AND #SK = :SK',
        expressionAttributeNames: {
          '#PK': 'PK',
          '#SK': 'SK',
        },
        expressionAttributeValues: {
          ':PK': AttributeValue(s: connectionPk(initiatorId)),
          ':SK': AttributeValue(s: connectionSk(role, domain, targetId)),
        },
      );

      if (response.items.isEmpty) {
        rethrow;
      }

      final row = response.items.first;
      return Connection.fromRow(row);
    }

    return connection;
  }

  @override
  Future<Iterable<Connection>> getConnections(String userId, {ConnectionRole? roleFilter}) async {
    final prefix = roleFilter != null ? '$_connectionSk${roleFilter.value}#' : _connectionSk;

    final response = await client.query(
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
      await client.transactWrite(
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
}
