part of 'db.dart';

mixin _Templates on _DatabaseBase implements ApiTemplateService {
  String get table;

  @override
  Future<TemplateItem> shareTemplate({
    required String coachId,
    required String studentId,
    required String masterTemplateId,
  }) async {
    final userKey = templatePk(coachId);
    final templateKey = templateSk(masterTemplateId);
    final masterResponse = await _client.batchGet(
      requestItems: {
        table: KeysAndProjection(
          keys: [
            {
              'PK': userKey,
              'SK': templateKey,
            },
            {
              'PK': userKey,
              'SK': userKey,
            },
          ],
        ),
      },
    );

    final (masterTemplate, coachItem) = switch (masterResponse.responses[table]) {
      [Map one, Map two] when one['PK'] == userKey && one['SK'] == templateKey => (
        TemplateItem.fromRow(one.cast<String, dynamic>()),
        two,
      ),
      [Map one, Map two] when two['PK'] == userKey && two['SK'] == templateKey => (
        TemplateItem.fromRow(two.cast<String, dynamic>()),
        one,
      ),
      _ => throw StateError('Master template not found'),
    };

    final now = DateTime.now().toIso8601String();
    final assignedBy = Profile.fromJson(coachItem);

    await _client.transactWrite(
      transactItems: [
        TransactWrite(
          put: Operation(
            tableName: table,
            expression: 'attribute_not_exists(PK)',
            value: {
              ...masterTemplate.toAttributeValue(),
              'PK': toDynamoType(templatePk(studentId)),
              'SK': templateSk(now),
              'source_template_id': masterTemplateId,
              'assigned_by': assignedBy.toAttributeValue(),
              'sync_enabled': true,
            },
          ),
        ),
        TransactWrite(
          put: Operation(
            tableName: table,
            expression: 'attribute_not_exists(PK)',
            value: {
              'PK': templatePk(coachId),
              'SK': '$_templateShareSk$masterTemplateId#$studentId',
              'student_template_id': now,
              'assigned_at': now,
            }.toAttributeValue(),
          ),
        ),
      ],
    );

    return masterTemplate.copyWith(assignedBy: assignedBy);
  }
}
