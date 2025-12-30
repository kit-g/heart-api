part of 'db.dart';

const _pk = 'USER#';
const _sk = 'CHART#';

mixin _Charts on _DatabaseBase implements ChartPreferenceService {
  String get table;

  static String pk(String userId) => '$_pk$userId';

  static String sk(String chartId) => '$_sk$chartId';

  @override
  Future<void> deleteChartPreference(String preferenceId, String userId) async {
    await client.delete(
      key: {
        'PK': AttributeValue(s: pk(userId)),
        'SK': AttributeValue(s: sk(preferenceId)),
      },
      tableName: table,
    );
  }

  @override
  Future<Iterable<ChartPreference>> getPreferences(String userId) async {
    final response = await client.query(
      tableName: table,
      keyConditionExpression: '#PK = :PK AND begins_with(#SK, :prefix)',
      expressionAttributeNames: {
        '#PK': 'PK',
        '#SK': 'SK',
      },
      expressionAttributeValues: {
        ':PK': AttributeValue(s: pk(userId)),
        ':prefix': AttributeValue(s: _sk),
      },
    );
    return response.items.map(ChartPreference.fromRow);
  }

  @override
  Future<ChartPreference> saveChartPreference(ChartPreference preference, String userId) async {
    await client.put(
      item: {
        'PK': AttributeValue(s: pk(userId)),
        'SK': AttributeValue(s: sk(preference.id!)),
        'type': AttributeValue(s: preference.type.value),
        'id': AttributeValue(s: preference.id),
        'data': ?switch (preference.data) {
          Map<String, dynamic> d => AttributeValue(m: d.map((k, v) => MapEntry(k, AttributeValue(s: v)))),
          null => null,
        },
      },
      tableName: table,
    );
    return preference;
  }
}
