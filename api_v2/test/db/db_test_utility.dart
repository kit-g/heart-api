import 'package:aws_client/dynamo_document.dart';
import 'package:heart/db/db.dart';
import 'package:mockito/mockito.dart';

import 'workouts_test.mocks.dart';

abstract class DatabaseTestBase {
  late MockDocumentClient mockClient;
  late Database db;
  final String tableName = 'test_table';

  void setupDatabase() {
    mockClient = MockDocumentClient();
    db = Database(client: mockClient, table: tableName);
  }

  /// Helper to mock a query response
  void mockQueryResponse(List<Map<String, dynamic>> items, {Map<String, dynamic>? lastEvaluatedKey}) {
    when(
      mockClient.query(
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
    ).thenAnswer(
      (_) async => QueryOutputDC(
        items: items,
        lastEvaluatedKey: lastEvaluatedKey ?? {},
        consumedCapacity: null,
        count: items.length,
        scannedCount: items.length,
      ),
    );
  }

  /// Helper to mock a get response
  void mockGetResponse(Map<String, dynamic>? item) {
    when(
      mockClient.get(
        tableName: anyNamed('tableName'),
        key: anyNamed('key'),
        consistentRead: anyNamed('consistentRead'),
        attributesToGet: anyNamed('attributesToGet'),
        expressionAttributeNames: anyNamed('expressionAttributeNames'),
        projectionExpression: anyNamed('projectionExpression'),
        returnConsumedCapacity: anyNamed('returnConsumedCapacity'),
      ),
    ).thenAnswer(
      (_) async => GetOutput(null, item ?? {}),
    );
  }
}
