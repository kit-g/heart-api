part of '../db.dart';

const _listGallery = '''
SELECT id, workout_id, key
FROM workout_images
WHERE user_id = @userId
  AND (@cursor::uuid IS NULL OR id < @cursor::uuid)
ORDER BY id DESC
LIMIT @limit
''';

const _insertImage = '''
INSERT INTO workout_images (workout_id, user_id, key)
VALUES (@workoutId::uuid, @userId, @key)
RETURNING id, workout_id, key
''';

const _deleteImage = '''
DELETE FROM workout_images
WHERE key = @key AND user_id = @userId AND workout_id = @workoutId::uuid
RETURNING id
''';

const _getUserImageKeys = '''
SELECT key 
FROM workout_images 
WHERE user_id = @userId
''';

const _getWorkoutImageKeys = '''
SELECT key 
FROM workout_images 
WHERE user_id = @userId 
  AND workout_id = @workoutId::uuid
''';
