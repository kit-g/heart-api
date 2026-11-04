part of '../db.dart';

const _getChartPreferences = '''
SELECT 
  exercise_id AS id, 
  chart_type AS type
FROM exercise_preferences 
WHERE user_id = @userId 
  AND chart_type IS NOT NULL 
ORDER BY created_at DESC
;
''';

const _saveChartPreference = '''
INSERT INTO exercise_preferences (user_id, exercise_id, chart_type)
VALUES (@userId, @exerciseId::uuid, @chartType)
ON CONFLICT (user_id, exercise_id)
DO 
  UPDATE SET chart_type = @chartType
''';

const _deleteChartPreference = '''
UPDATE exercise_preferences 
SET chart_type = NULL
WHERE exercise_id = @id::uuid
  AND user_id = @userId
  ;
''';
