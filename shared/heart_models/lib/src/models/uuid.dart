import 'package:uuid/v7.dart';

var _uuid = const UuidV7();

String uuidV7() => _uuid.generate();

final _v7 = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);

/// Whether [id] has the shape of a UUIDv7 — the only id format the platform
/// mints or accepts. The shared wire predicate: the API guards client-sent
/// ids with it before any `::uuid` cast, and the app validates local rows
/// with it, so a Firebase-era or garbage id fails cleanly on both sides.
bool isUuidV7(String id) => _v7.hasMatch(id);

/// The instant a v7 uuid was minted — its leading 48 bits are milliseconds
/// since the Unix epoch. Null when [id] is not a v7 uuid, which is how callers
/// fall back on Firebase-era ids, which were timestamps outright.
DateTime? timestampOfUuidV7(String id) {
  if (!_v7.hasMatch(id)) return null;
  final ms = int.parse(id.substring(0, 8) + id.substring(9, 13), radix: 16);
  return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
}

abstract mixin class HasUuid {
  final String uuid = const UuidV7().generate();
}
