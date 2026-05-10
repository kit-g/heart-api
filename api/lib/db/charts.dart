part of 'db.dart';

mixin _Charts on _DatabaseBase implements ChartPreferenceService {
  @override
  Future<Iterable<ChartPreference>> getPreferences(String userId) async {
    final result = await _pool.execute(
      Sql.named(
        '''
      SELECT exercise_id AS id, chart_type AS type 
      FROM chart_preferences WHERE user_id = @userId ORDER BY created_at DESC;
      ''',
      ),
      parameters: {'userId': userId},
    );
    return result.map((row) => ChartPreference.fromRow(row.toColumnMap()));
  }

  @override
  Future<ChartPreference> saveChartPreference(ChartPreference preference, String userId) async {
    await _pool.execute(
      Sql.named(
        '''
      INSERT INTO chart_preferences (user_id, exercise_id, chart_type) 
      VALUES (@userId, @exerciseId, @chartType) 
      ON CONFLICT (user_id, exercise_id) 
      DO UPDATE SET chart_type = @chartType
      ''',
      ),
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
      Sql.named('DELETE FROM chart_preferences WHERE exercise_id = @id AND user_id = @userId'),
      parameters: {'id': preferenceId, 'userId': userId},
    );
  }
}
