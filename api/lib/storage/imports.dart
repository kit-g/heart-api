part of 's3.dart';

mixin _Imports on _StorageBase implements ImportStorage {
  @override
  Future<({String key, bool already})> keep({
    required String userId,
    required ImportSource source,
    required List<int> bytes,
    required KeptImport as,
  }) async {
    final key = keptImportKey(userId: userId, source: source, bytes: bytes, as: as);
    if (await exists(contentBucket, key)) return (key: key, already: true);
    await _upload(key, bytes, 'text/csv');
    return (key: key, already: false);
  }
}
