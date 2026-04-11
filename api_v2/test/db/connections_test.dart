import 'package:aws_client/dynamo_db_2012_08_10.dart' as db_api;
import 'package:aws_client/dynamo_document.dart';
import 'package:heart/models/connections.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'db_test_utility.dart';

void main() {
  final testEnv = ConnectionsTestEnv();

  setUp(() {
    testEnv.setupDatabase();
  });

  group('Connections DB', () {
    final initiatorId = 'user_initiator';
    final targetId = 'user_target';
    final role = ConnectionRole.coach;
    final domain = ConnectionDomain.fitness;

    test('createConnection calls transactWrite with correct parameters', () async {
      when(
        testEnv.mockClient.transactWrite(
          transactItems: anyNamed('transactItems'),
          clientRequestToken: anyNamed('clientRequestToken'),
          returnConsumedCapacity: anyNamed('returnConsumedCapacity'),
          returnItemCollectionMetrics: anyNamed('returnItemCollectionMetrics'),
        ),
      ).thenAnswer((_) async => db_api.TransactWriteItemsOutput());

      final connection = await testEnv.db.createConnection(
        initiatorId: initiatorId,
        targetId: targetId,
        role: role,
        domain: domain,
      );

      expect(connection.targetId, equals(targetId));
      expect(connection.role, equals(role));
      expect(connection.status, equals(ConnectionStatus.pending));

      verify(
        testEnv.mockClient.transactWrite(
          transactItems: argThat(
            predicate((List<TransactWrite> items) {
              if (items.length != 2) return false;
              final put1 = items[0].put!;
              final put2 = items[1].put!;
              return put1.value['PK']?.s == 'USER#$initiatorId' &&
                  put1.value['SK']?.s == 'CONN#COACH#FITNESS#$targetId' &&
                  put2.value['PK']?.s == 'USER#$targetId' &&
                  put2.value['SK']?.s == 'CONN#STUDENT#FITNESS#$initiatorId';
            }),
            named: 'transactItems',
          ),
        ),
      ).called(1);
    });

    test('createConnection handles conflict and returns existing connection', () async {
      when(
        testEnv.mockClient.transactWrite(
          transactItems: anyNamed('transactItems'),
          clientRequestToken: anyNamed('clientRequestToken'),
          returnConsumedCapacity: anyNamed('returnConsumedCapacity'),
          returnItemCollectionMetrics: anyNamed('returnItemCollectionMetrics'),
        ),
      ).thenThrow(
        TransactionCanceledException(
          message:
              'Transaction cancelled, please refer to CancellationReasons for further information [ConditionalCheckFailed, None]',
        ),
      );

      final existingRow = {
        'targetId': targetId,
        'role': 'COACH',
        'domain': 'fitness',
        'status': 'active',
        'createdAt': DateTime.now().toIso8601String(),
      };

      testEnv.mockQueryResponse([existingRow]);

      final connection = await testEnv.db.createConnection(
        initiatorId: initiatorId,
        targetId: targetId,
        role: role,
        domain: domain,
      );

      expect(connection.status, equals(ConnectionStatus.active));
      verify(
        testEnv.mockClient.query(
          tableName: anyNamed('tableName'),
          expressionAttributeValues: argThat(
            containsPair(':SK', isA<AttributeValue>().having((a) => a.s, 's', contains(targetId))),
            named: 'expressionAttributeValues',
          ),
          keyConditionExpression: anyNamed('keyConditionExpression'),
          expressionAttributeNames: anyNamed('expressionAttributeNames'),
          scanIndexForward: anyNamed('scanIndexForward'),
          limit: anyNamed('limit'),
          exclusiveStartKey: anyNamed('exclusiveStartKey'),
          consistentRead: anyNamed('consistentRead'),
          indexName: anyNamed('indexName'),
          projectionExpression: anyNamed('projectionExpression'),
          filterExpression: anyNamed('filterExpression'),
          attributesToGet: anyNamed('attributesToGet'),
          conditionalOperator: anyNamed('conditionalOperator'),
          keyConditions: anyNamed('keyConditions'),
          queryFilter: anyNamed('queryFilter'),
          returnConsumedCapacity: anyNamed('returnConsumedCapacity'),
          select: anyNamed('select'),
        ),
      ).called(1);
    });

    test('getConnections calls query with correct prefix', () async {
      final mockRows = [
        {
          'targetId': 'target1',
          'role': 'STUDENT',
          'domain': 'fitness',
          'status': 'active',
          'createdAt': DateTime.now().toIso8601String(),
        },
      ];

      testEnv.mockQueryResponse(mockRows);

      final connections = await testEnv.db.getConnections(initiatorId, roleFilter: ConnectionRole.student);

      expect(connections.length, equals(1));
      expect(connections.first.targetId, equals('target1'));

      verify(
        testEnv.mockClient.query(
          tableName: anyNamed('tableName'),
          expressionAttributeValues: argThat(
            containsPair(':prefix', isA<AttributeValue>().having((a) => a.s, 's', 'CONN#STUDENT#')),
            named: 'expressionAttributeValues',
          ),
          keyConditionExpression: anyNamed('keyConditionExpression'),
          expressionAttributeNames: anyNamed('expressionAttributeNames'),
          scanIndexForward: anyNamed('scanIndexForward'),
          limit: anyNamed('limit'),
          exclusiveStartKey: anyNamed('exclusiveStartKey'),
          consistentRead: anyNamed('consistentRead'),
          indexName: anyNamed('indexName'),
          projectionExpression: anyNamed('projectionExpression'),
          filterExpression: anyNamed('filterExpression'),
          attributesToGet: anyNamed('attributesToGet'),
          conditionalOperator: anyNamed('conditionalOperator'),
          keyConditions: anyNamed('keyConditions'),
          queryFilter: anyNamed('queryFilter'),
          returnConsumedCapacity: anyNamed('returnConsumedCapacity'),
          select: anyNamed('select'),
        ),
      ).called(1);
    });

    test('getConnection returns model if exists', () async {
      final row = {
        'targetId': targetId,
        'role': 'COACH',
        'domain': 'fitness',
        'status': 'active',
        'createdAt': DateTime.now().toIso8601String(),
      };

      testEnv.mockGetResponse(row);

      final connection = await testEnv.db.getConnection(
        initiatorId: initiatorId,
        targetId: targetId,
        role: role,
        domain: domain,
      );

      expect(connection, isNotNull);
      expect(connection!.status, equals(ConnectionStatus.active));
    });

    test('getConnection returns null if not exists', () async {
      testEnv.mockGetResponse(null);

      final connection = await testEnv.db.getConnection(
        initiatorId: initiatorId,
        targetId: targetId,
        role: role,
        domain: domain,
      );

      expect(connection, isNull);
    });

    test('deleteConnection calls transactWrite', () async {
      when(
        testEnv.mockClient.transactWrite(
          transactItems: anyNamed('transactItems'),
          clientRequestToken: anyNamed('clientRequestToken'),
          returnConsumedCapacity: anyNamed('returnConsumedCapacity'),
          returnItemCollectionMetrics: anyNamed('returnItemCollectionMetrics'),
        ),
      ).thenAnswer((_) async => db_api.TransactWriteItemsOutput());

      await testEnv.db.deleteConnection(
        initiatorId: initiatorId,
        targetId: targetId,
        role: role,
        domain: domain,
      );

      verify(
        testEnv.mockClient.transactWrite(
          transactItems: argThat(
            predicate((List<TransactWrite> items) {
              return items.length == 2 && items[0].delete != null && items[1].delete != null;
            }),
            named: 'transactItems',
          ),
        ),
      ).called(1);
    });

    test('changeConnectionStatus updates status', () async {
      final row = {
        'targetId': targetId,
        'role': 'COACH',
        'domain': 'fitness',
        'status': 'pending',
        'createdAt': DateTime.now().toIso8601String(),
      };

      testEnv.mockGetResponse(row);

      when(
        testEnv.mockClient.transactWrite(
          transactItems: anyNamed('transactItems'),
          clientRequestToken: anyNamed('clientRequestToken'),
          returnConsumedCapacity: anyNamed('returnConsumedCapacity'),
          returnItemCollectionMetrics: anyNamed('returnItemCollectionMetrics'),
        ),
      ).thenAnswer((_) async => db_api.TransactWriteItemsOutput());

      final connection = await testEnv.db.changeConnectionStatus(
        initiatorId: initiatorId,
        targetId: targetId,
        role: role,
        domain: domain,
        newStatus: ConnectionStatus.active,
      );

      expect(connection.status, equals(ConnectionStatus.active));

      verify(
        testEnv.mockClient.transactWrite(
          transactItems: argThat(
            predicate((List<TransactWrite> items) {
              return items.length == 2 &&
                  items[0].update?.updateExpression == 'SET #status = :newStatus' &&
                  items[0].update?.expressionAttributeValues?[':newStatus']?.s == 'active';
            }),
            named: 'transactItems',
          ),
        ),
      ).called(1);
    });

    test('changeConnectionStatus throws on invalid transition', () async {
      final row = {
        'targetId': targetId,
        'role': 'COACH',
        'domain': 'fitness',
        'status': 'active',
        'createdAt': DateTime.now().toIso8601String(),
      };

      testEnv.mockGetResponse(row);

      expect(
        () => testEnv.db.changeConnectionStatus(
          initiatorId: initiatorId,
          targetId: targetId,
          role: role,
          domain: domain,
          newStatus: ConnectionStatus.pending,
        ),
        throwsStateError,
      );
    });
  });
}

class ConnectionsTestEnv extends DatabaseTestBase {}
