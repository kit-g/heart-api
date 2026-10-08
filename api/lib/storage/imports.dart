part of 's3.dart';

mixin _Imports on _StorageBase implements ImportStorage {
  @override
  Future<String> park({required String userId, required ImportSource source, required List<int> bytes}) async {
    final key = parkedImportKey(userId: userId, source: source, bytes: bytes);
    await _upload(key, bytes, 'text/csv');
    return key;
  }
}
