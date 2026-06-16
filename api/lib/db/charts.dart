part of 'db.dart';

mixin _Charts on _DatabaseBase implements ChartPreferenceService {
  @override
  Future<Iterable<ChartPreference>> getPreferences(String userId) async {
    final result = await _pool.execute(
      _getChartPreferences.toSql(),
      parameters: {'userId': userId},
    );
    return result.map((row) => ChartPreference.fromRow(row.toColumnMap()));
  }

  @override
  Future<ChartPreference> saveChartPreference(ChartPreference preference, String userId) async {
    await _pool.execute(
      _saveChartPreference.toSql(),
      parameters: {
        'userId': userId,
        'exerciseId': preference.id!,
        'chartType': preference.type.value,
      },
    );
    return preference;
  }

  @override
  Future<void> deleteChartPreference(String preferenceId, String userId) async {
    await _pool.execute(
      _deleteChartPreference.toSql(),
      parameters: {'id': preferenceId, 'userId': userId},
    );
  }
}
