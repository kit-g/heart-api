import 'dart:convert';

import 'package:aws_client/dynamo_document.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'db_test_utility.dart';

@GenerateMocks([DocumentClient])
void main() {
  final testEnv = WorkoutsTestEnv();

  setUp(() {
    testEnv.setupDatabase();
  });

  group('Workouts DB', () {
    test('getWorkouts calls query with correct parameters', () async {
      final userId = 'user123';
      final targetUserId = 'target456';
      final now = DateTime.utc(2024, 1, 1);

      final mockItems = [
        {
          'PK': 'USER#target456',
          'SK': 'WORKOUT#workout789',
          'name': 'Test Workout',
          'start': now.toIso8601String(),
          'exercises': [],
        },
      ];

      testEnv.mockQueryResponse(mockItems, lastEvaluatedKey: {'SK': 'WORKOUT#workout789'});

      final response = await testEnv.db.getWorkouts(
        userId: userId,
        targetUserId: targetUserId,
        imageUrl: (key) => 'https://cdn/$key',
      );

      verify(
        testEnv.mockClient.query(
          tableName: anyNamed('tableName'),
          keyConditionExpression: anyNamed('keyConditionExpression'),
          expressionAttributeNames: anyNamed('expressionAttributeNames'),
          expressionAttributeValues: anyNamed('expressionAttributeValues'),
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

      expect(response.workouts.length, equals(1));
      expect(response.workouts.first.id, equals('workout789'));
      expect(response.workouts.first.name, equals('Test Workout'));

      // Cursor is base64 of workout789
      final expectedCursor = base64Encode(utf8.encode('workout789'));
      expect(response.cursor, equals(expectedCursor));
    });

    test('getWorkouts handles cursor correctly', () async {
      final userId = 'user123';
      final targetUserId = 'target456';
      final cursorId = 'prevWorkout';
      final cursor = base64Encode(utf8.encode(cursorId));

      testEnv.mockQueryResponse([]);

      await testEnv.db.getWorkouts(
        userId: userId,
        targetUserId: targetUserId,
        imageUrl: (key) => key,
        cursor: cursor,
      );

      verify(
        testEnv.mockClient.query(
          tableName: anyNamed('tableName'),
          keyConditionExpression: anyNamed('keyConditionExpression'),
          expressionAttributeNames: anyNamed('expressionAttributeNames'),
          expressionAttributeValues: anyNamed('expressionAttributeValues'),
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
  });
}

class WorkoutsTestEnv extends DatabaseTestBase {}
