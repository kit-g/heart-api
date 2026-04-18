// ignore_for_file: avoid_dynamic_calls
import 'dart:convert';

import 'package:aws_client/dynamo_db_2012_08_10.dart' as db_api;
import 'package:aws_client/dynamo_document.dart';
import 'package:heart/models/errors.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'db_test_utility.dart';

void main() {
  final testEnv = TemplatesTestEnv();

  setUp(() {
    testEnv.setupDatabase();
  });

  final coachId = 'coach_user';
  final studentId = 'student_user';
  final templateId = 'template_123';

  final coachKey = 'USER#$coachId';
  final studentKey = 'USER#$studentId';
  final templateKey = 'TEMPLATE#$templateId';

  final templateRow = {
    'PK': coachKey,
    'SK': templateKey,
    'name': 'Push Day',
    'order': 1,
    'exercises': [],
    'sync_enabled': true,
  };

  final coachProfileRow = {
    'PK': coachKey,
    'SK': coachKey,
    'username': 'Coach Name',
    'avatar': null,
  };

  final studentProfileRow = {
    'PK': studentKey,
    'SK': studentKey,
    'username': 'Student Name',
    'avatar': null,
  };

  group('getTemplates', () {
    test('returns paginated template list', () async {
      testEnv.mockQueryResponse([templateRow]);

      final result = await testEnv.db.getTemplates(userId: coachId);

      expect(result.templates.length, equals(1));
      expect(result.templates.first.name, equals('Push Day'));
      expect(result.cursor, isNull);
    });

    test('passes cursor as exclusiveStartKey', () async {
      final cursorValue = base64Encode(utf8.encode(templateKey));
      testEnv.mockQueryResponse([]);

      await testEnv.db.getTemplates(userId: coachId, cursor: cursorValue);

      verify(
        testEnv.mockClient.query(
          tableName: anyNamed('tableName'),
          exclusiveStartKey: argThat(
            predicate((Map? key) => key?['SK']?.s == templateKey),
            named: 'exclusiveStartKey',
          ),
          keyConditionExpression: anyNamed('keyConditionExpression'),
          expressionAttributeNames: anyNamed('expressionAttributeNames'),
          expressionAttributeValues: anyNamed('expressionAttributeValues'),
          scanIndexForward: anyNamed('scanIndexForward'),
          limit: anyNamed('limit'),
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

    test('returns cursor from lastEvaluatedKey', () async {
      testEnv.mockQueryResponse(
        [templateRow],
        lastEvaluatedKey: {'SK': templateKey},
      );

      final result = await testEnv.db.getTemplates(userId: coachId);

      expect(result.cursor, isNotNull);
    });
  });

  group('getTemplateShares', () {
    final shareRow = {
      'PK': coachKey,
      'SK': 'TEMPLATE_SHARE#$templateId#$studentId',
      'student_template_id': '2025-01-01T12:00:00.000Z',
      'template_name': 'Push Day',
      'assigned_to': studentProfileRow,
      'assigned_at': '2025-01-01T12:00:00.000Z',
    };

    test('returns paginated share list', () async {
      testEnv.mockQueryResponse([shareRow]);

      final result = await testEnv.db.getTemplateShares(userId: coachId);

      expect(result.shares.length, equals(1));
      expect(result.shares.first.templateName, equals('Push Day'));
      expect(result.shares.first.assignedTo.name, equals('Student Name'));
    });

    test('queries with TEMPLATE_SHARE# prefix', () async {
      testEnv.mockQueryResponse([]);

      await testEnv.db.getTemplateShares(userId: coachId);

      verify(
        testEnv.mockClient.query(
          tableName: anyNamed('tableName'),
          expressionAttributeValues: argThat(
            containsPair(':PREFIX', isA<AttributeValue>().having((a) => a.s, 's', startsWith('TEMPLATE_SHARE#'))),
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
  });

  group('shareTemplate', () {
    void mockTransactWrite() {
      when(
        testEnv.mockClient.transactWrite(
          transactItems: anyNamed('transactItems'),
          clientRequestToken: anyNamed('clientRequestToken'),
          returnConsumedCapacity: anyNamed('returnConsumedCapacity'),
          returnItemCollectionMetrics: anyNamed('returnItemCollectionMetrics'),
        ),
      ).thenAnswer((_) async => db_api.TransactWriteItemsOutput());
    }

    test('fetches template and profiles, writes share and student copy', () async {
      testEnv.mockBatchGetResponse([templateRow, coachProfileRow, studentProfileRow]);
      mockTransactWrite();

      final result = await testEnv.db.shareTemplate(
        coachId: coachId,
        targetUserId: studentId,
        masterTemplateId: templateId,
      );

      expect(result.templateName, equals('Push Day'));
      expect(result.assignedTo.name, equals('Student Name'));

      verify(
        testEnv.mockClient.transactWrite(
          transactItems: argThat(
            predicate((List<TransactWrite> items) {
              if (items.length != 2) return false;
              final studentTemplatePut = items[0].put!;
              final sharePut = items[1].put!;
              return studentTemplatePut.value['PK']?.s == studentKey &&
                  sharePut.value['PK']?.s == coachKey &&
                  (sharePut.value['SK']?.s as String?)?.startsWith('TEMPLATE_SHARE#$templateId#') == true &&
                  sharePut.value['template_name']?.s == 'Push Day';
            }),
            named: 'transactItems',
          ),
        ),
      ).called(1);
    });

    test('returns existing share on duplicate', () async {
      testEnv.mockBatchGetResponse([templateRow, coachProfileRow, studentProfileRow]);

      when(
        testEnv.mockClient.transactWrite(
          transactItems: anyNamed('transactItems'),
          clientRequestToken: anyNamed('clientRequestToken'),
          returnConsumedCapacity: anyNamed('returnConsumedCapacity'),
          returnItemCollectionMetrics: anyNamed('returnItemCollectionMetrics'),
        ),
      ).thenThrow(
        TransactionCanceledException(
          message: 'Transaction cancelled [None, ConditionalCheckFailed]',
        ),
      );

      final existingShareRow = {
        'PK': coachKey,
        'SK': 'TEMPLATE_SHARE#$templateId#$studentId',
        'student_template_id': '2025-01-01T00:00:00.000Z',
        'template_name': 'Push Day',
        'assigned_to': studentProfileRow,
        'assigned_at': '2025-01-01T00:00:00.000Z',
      };

      testEnv.mockGetResponse(existingShareRow);

      final result = await testEnv.db.shareTemplate(
        coachId: coachId,
        targetUserId: studentId,
        masterTemplateId: templateId,
      );

      expect(result.templateName, equals('Push Day'));
    });

    test('throws StateError when template not found', () async {
      testEnv.mockBatchGetResponse([coachProfileRow, studentProfileRow]);

      expect(
        () => testEnv.db.shareTemplate(
          coachId: coachId,
          targetUserId: studentId,
          masterTemplateId: templateId,
        ),
        throwsStateError,
      );
    });
  });

  group('deleteTemplate', () {
    void mockTransactWrite() {
      when(
        testEnv.mockClient.transactWrite(
          transactItems: anyNamed('transactItems'),
          clientRequestToken: anyNamed('clientRequestToken'),
          returnConsumedCapacity: anyNamed('returnConsumedCapacity'),
          returnItemCollectionMetrics: anyNamed('returnItemCollectionMetrics'),
        ),
      ).thenAnswer((_) async => db_api.TransactWriteItemsOutput());
    }

    test('deletes template and all share records', () async {
      final shareRow = {
        'PK': coachKey,
        'SK': 'TEMPLATE_SHARE#$templateId#$studentId',
      };
      testEnv.mockQueryResponse([shareRow]);
      mockTransactWrite();

      await testEnv.db.deleteTemplate(coachId: coachId, templateId: templateId);

      verify(
        testEnv.mockClient.transactWrite(
          transactItems: argThat(
            predicate((List<TransactWrite> items) {
              if (items.length != 2) return false;
              final templateDelete = items[0].delete!;
              final shareDelete = items[1].delete!;
              return templateDelete.value['SK']?.s == templateKey &&
                  shareDelete.value['SK']?.s == 'TEMPLATE_SHARE#$templateId#$studentId';
            }),
            named: 'transactItems',
          ),
        ),
      ).called(1);
    });

    test('deletes only template when no shares exist', () async {
      testEnv.mockQueryResponse([]);
      mockTransactWrite();

      await testEnv.db.deleteTemplate(coachId: coachId, templateId: templateId);

      verify(
        testEnv.mockClient.transactWrite(
          transactItems: argThat(
            predicate((List<TransactWrite> items) => items.length == 1 && items[0].delete != null),
            named: 'transactItems',
          ),
        ),
      ).called(1);
    });
  });

  group('deleteShare', () {
    final shareId = '$studentId|$templateId';
    final shareSk = 'TEMPLATE_SHARE#$templateId#$studentId';
    final studentTemplateSk = 'TEMPLATE#2025-01-01T12:00:00.000Z';

    final shareRow = {
      'PK': coachKey,
      'SK': shareSk,
      'student_template_id': '2025-01-01T12:00:00.000Z',
      'template_name': 'Push Day',
      'assigned_to': studentProfileRow,
      'assigned_at': '2025-01-01T12:00:00.000Z',
    };

    test('deletes share and student copy atomically', () async {
      testEnv.mockGetResponse(shareRow);

      when(
        testEnv.mockClient.transactWrite(
          transactItems: anyNamed('transactItems'),
          clientRequestToken: anyNamed('clientRequestToken'),
          returnConsumedCapacity: anyNamed('returnConsumedCapacity'),
          returnItemCollectionMetrics: anyNamed('returnItemCollectionMetrics'),
        ),
      ).thenAnswer((_) async => db_api.TransactWriteItemsOutput());

      await testEnv.db.deleteShare(coachId: coachId, shareId: shareId);

      verify(
        testEnv.mockClient.transactWrite(
          transactItems: argThat(
            predicate((List<TransactWrite> items) {
              if (items.length != 2) return false;
              final shareDelete = items[0].delete!;
              final studentCopyDelete = items[1].delete!;
              return shareDelete.value['SK']?.s == shareSk &&
                  studentCopyDelete.value['PK']?.s == studentKey &&
                  studentCopyDelete.value['SK']?.s == studentTemplateSk;
            }),
            named: 'transactItems',
          ),
        ),
      ).called(1);
    });

    test('throws NotFound when share does not exist', () async {
      testEnv.mockGetResponse(null);

      expect(
        () => testEnv.db.deleteShare(coachId: coachId, shareId: shareId),
        throwsA(isA<NotFound>()),
      );
    });

    test('throws ArgumentError on invalid shareId format', () async {
      expect(
        () => testEnv.db.deleteShare(coachId: coachId, shareId: 'invalid'),
        throwsArgumentError,
      );
    });
  });
}

class TemplatesTestEnv extends DatabaseTestBase {
  void mockBatchGetResponse(List<Map<String, dynamic>> items) {
    when(
      mockClient.batchGet(
        requestItems: anyNamed('requestItems'),
        returnConsumedCapacity: anyNamed('returnConsumedCapacity'),
      ),
    ).thenAnswer(
      (_) async => BatchGetOutput([], {tableName: items}, {}),
    );
  }
}
