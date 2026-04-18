part of 'db.dart';

mixin _Templates on _DatabaseBase implements ApiTemplateService {
  String get table;

  @override
  Future<TemplateShareItem> shareTemplate({
    required String coachId,
    required String targetUserId,
    required String masterTemplateId,
  }) async {
    final coachKey = templatePk(coachId);
    final targetUserKey = templatePk(targetUserId);
    final templateKey = templateSk(masterTemplateId);
    final masterResponse = await _client.batchGet(
      requestItems: {
        table: KeysAndProjection(
          keys: [
            {'PK': coachKey, 'SK': templateKey},
            {'PK': coachKey, 'SK': coachKey},
            {'PK': targetUserKey, 'SK': targetUserKey},
          ],
        ),
      },
    );

    final items = (masterResponse.responses[table] ?? []).cast<Map<String, dynamic>>();
    final templateRow = items.firstWhere(
      (item) => item['SK'] == templateKey,
      orElse: () => throw StateError('Master template not found'),
    );
    final coachRow = items.firstWhere(
      (item) => item['PK'] == coachKey && item['SK'] == coachKey,
      orElse: () => throw StateError('Coach profile not found'),
    );
    final studentRow = items.firstWhere(
      (item) => item['PK'] == targetUserKey && item['SK'] == targetUserKey,
      orElse: () => throw StateError('Student profile not found'),
    );

    final masterTemplate = TemplateItem.fromRow(templateRow);
    final now = DateTime.now().toIso8601String();
    final assignedBy = Profile.fromJson(coachRow);
    final studentProfile = Profile.fromJson(studentRow);

    final shareSk = '$_templateShareSk$masterTemplateId#$targetUserId';

    try {
      await _client.transactWrite(
        transactItems: [
          TransactWrite(
            put: Operation(
              tableName: table,
              expression: 'attribute_not_exists(PK)',
              value: {
                ...masterTemplate.toAttributeValue(),
                'PK': toDynamoType(templatePk(targetUserId)),
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
                'PK': coachKey,
                'SK': shareSk,
                'student_template_id': now,
                'template_name': masterTemplate.name,
                'assigned_to': studentRow,
                'assigned_at': now,
              }.toAttributeValue(),
            ),
          ),
        ],
      );
    } on TransactionCanceledException catch (e) {
      if (e.message case String message when !message.contains('ConditionalCheckFailed')) {
        rethrow;
      }
      // template already shared — return existing share record
      final response = await _client.get(
        tableName: table,
        key: {
          'PK': AttributeValue(s: coachKey),
          'SK': AttributeValue(s: shareSk),
        },
      );

      return TemplateShareItem.fromRow(response.item);
    }

    return TemplateShareItem(
      id: '$targetUserId|$now',
      studentTemplateId: now,
      templateName: masterTemplate.name,
      assignedTo: studentProfile,
      assignedAt: DateTime.parse(now),
    );
  }

  @override
  Future<TemplateListResponse> getTemplates({
    required String userId,
    String? cursor,
    int? pageSize = 30,
  }) async {
    final response = await _client.query(
      tableName: table,
      keyConditionExpression: '#PK = :PK AND begins_with(#SK, :PREFIX)',
      expressionAttributeNames: {'#PK': 'PK', '#SK': 'SK'},
      expressionAttributeValues: {
        ':PK': AttributeValue(s: templatePk(userId)),
        ':PREFIX': AttributeValue(s: _templateSk),
      },
      scanIndexForward: false,
      limit: pageSize,
      exclusiveStartKey: switch (cursor?.fromBase64()) {
        String s when s.isNotEmpty => {
          'PK': AttributeValue(s: templatePk(userId)),
          'SK': AttributeValue(s: s),
        },
        _ => null,
      },
    );

    return TemplateListResponse(
      templates: response.items.map((item) => TemplateItem.fromRow(item)).toList(),
      cursor: (response.lastEvaluatedKey['SK'] as String?)?.toBase64(),
    );
  }

  @override
  Future<TemplateShareListResponse> getTemplateShares({
    required String userId,
    String? cursor,
    int? pageSize = 30,
  }) async {
    final response = await _client.query(
      tableName: table,
      keyConditionExpression: '#PK = :PK AND begins_with(#SK, :PREFIX)',
      expressionAttributeNames: {'#PK': 'PK', '#SK': 'SK'},
      expressionAttributeValues: {
        ':PK': AttributeValue(s: templatePk(userId)),
        ':PREFIX': AttributeValue(s: _templateShareSk),
      },
      scanIndexForward: false,
      limit: pageSize,
      exclusiveStartKey: switch (cursor?.fromBase64()) {
        String s when s.isNotEmpty => {
          'PK': AttributeValue(s: templatePk(userId)),
          'SK': AttributeValue(s: s),
        },
        _ => null,
      },
    );

    return TemplateShareListResponse(
      shares: response.items.map((item) => TemplateShareItem.fromRow(item)).toList(),
      cursor: (response.lastEvaluatedKey['SK'] as String?)?.toBase64(),
    );
  }

  @override
  Future<void> deleteTemplate({
    required String coachId,
    required String templateId,
  }) async {
    final coachKey = templatePk(coachId);

    final sharesResponse = await _client.query(
      tableName: table,
      keyConditionExpression: '#PK = :PK AND begins_with(#SK, :PREFIX)',
      expressionAttributeNames: {'#PK': 'PK', '#SK': 'SK'},
      expressionAttributeValues: {
        ':PK': AttributeValue(s: coachKey),
        ':PREFIX': AttributeValue(s: '$_templateShareSk$templateId#'),
      },
    );

    await _client.transactWrite(
      transactItems: [
        TransactWrite(
          delete: Operation(
            tableName: table,
            expression: 'attribute_exists(PK)',
            value: {
              'PK': AttributeValue(s: coachKey),
              'SK': AttributeValue(s: templateSk(templateId)),
            },
          ),
        ),
        ...sharesResponse.items.map(
          (item) => TransactWrite(
            delete: Operation(
              tableName: table,
              expression: 'attribute_exists(PK)',
              value: {
                'PK': AttributeValue(s: item['PK'] as String),
                'SK': AttributeValue(s: item['SK'] as String),
              },
            ),
          ),
        ),
      ],
    );
  }

  @override
  Future<void> deleteShare({
    required String coachId,
    required String shareId,
  }) async {
    final parts = shareId.split('|');
    if (parts.length != 2) throw ArgumentError('Invalid share ID: $shareId');
    final studentId = parts[0];
    final masterTemplateId = parts[1];

    final coachKey = templatePk(coachId);
    final shareSk = '$_templateShareSk$masterTemplateId#$studentId';

    final response = await _client.get(
      tableName: table,
      key: {
        'PK': AttributeValue(s: coachKey),
        'SK': AttributeValue(s: shareSk),
      },
    );

    final studentTemplateId = switch (response.item['student_template_id']) {
      String s when s.isNotEmpty => s,
      _ => throw NotFound(type: 'TemplateShare', id: shareId),
    };

    await _client.transactWrite(
      transactItems: [
        TransactWrite(
          delete: Operation(
            tableName: table,
            expression: 'attribute_exists(PK)',
            value: {
              'PK': AttributeValue(s: coachKey),
              'SK': AttributeValue(s: shareSk),
            },
          ),
        ),
        TransactWrite(
          delete: Operation(
            tableName: table,
            expression: 'attribute_exists(PK)',
            value: {
              'PK': AttributeValue(s: templatePk(studentId)),
              'SK': AttributeValue(s: templateSk(studentTemplateId)),
            },
          ),
        ),
      ],
    );
  }
}
