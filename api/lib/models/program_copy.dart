import 'package:heart_models/heart_models.dart';

final _uuid = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', caseSensitive: false);

/// Every id in a library program's body, wherever it sits: as a key or a value, in
/// sessions, phases, tests, rules and their ladders, set targets. Walking the whole
/// document means a later id-bearing key is covered without anyone remembering it.
Set<String> idsIn(Object? json) {
  return switch (json) {
    final String value when _uuid.hasMatch(value) => {value},
    final Map map => {
      for (final MapEntry(:key, :value) in map.entries) ...{...idsIn(key), ...idsIn(value)},
    },
    final List list => {for (final value in list) ...idsIn(value)},
    _ => const {},
  };
}

/// [json] with each id replaced by what [ids] says.
Object? remapIds(Object? json, Map<String, String> ids) {
  return switch (json) {
    final String value => ids[value] ?? value,
    final Map map => {
      for (final MapEntry(:key, :value) in map.entries) ids[key] ?? key: remapIds(value, ids),
    },
    final List list => [for (final value in list) remapIds(value, ids)],
    final other => other,
  };
}

/// Gives every session, exercise and set an id, so a later version can name the
/// same rows and an update knows them. An id the device sent stays.
Map<String, dynamic> withRowIds(Map<String, dynamic> body) {
  Map<String, dynamic> identified(Map row, {String? children, Map<String, dynamic> Function(Map)? child}) {
    return {
      ...row.cast<String, dynamic>(),
      'id': row['id'] ?? uuidV7(),
      if (children != null && row[children] is List)
        children: [for (final each in row[children] as List) child!(each as Map)],
    };
  }

  Map<String, dynamic> set(Map row) => identified(row);
  Map<String, dynamic> exercise(Map row) => identified(row, children: 'sets', child: set);
  Map<String, dynamic> session(Map row) => identified(row, children: 'exercises', child: exercise);

  return {
    ...body,
    if (body['sessions'] is List) 'sessions': [for (final each in body['sessions'] as List) session(each as Map)],
  };
}

/// What a copy of [body] needs: [exercises] for ids the student has an answer to,
/// and a new v7 for the rest. Anything else would read as no link on a workout or a
/// skip. [known] is what an earlier send or update already chose.
Map<String, String> copyIds(
  Map<String, dynamic> body, {
  required Map<String, String> exercises,
  Map<String, String> known = const {},
}) {
  return {
    for (final id in idsIn(body)) id: known[id] ?? exercises[id] ?? uuidV7(),
  };
}
