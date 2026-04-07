part of 's3.dart';

mixin _Exercises on _StorageBase implements ExerciseService {
  @override
  Future<Map<String, dynamic>> getExercises(userId, {String? locale}) async {
    final file = await _client.getObject(bucket: exerciseBucket, key: 'library/exercises_$locale.json');
    final bytes = file.body;
    if (bytes == null) return {};
    return jsonDecode(utf8.decode(bytes));
  }
}
