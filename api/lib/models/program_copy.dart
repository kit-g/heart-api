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
/// same rows and an update knows them. A v7 id the device sent stays; anything
/// else is one the parser would drop, so it gets a v7 like a row with none.
Map<String, dynamic> withRowIds(Map<String, dynamic> body) {
  Map<String, dynamic> identified(Map row, {String? children, Map<String, dynamic> Function(Map)? child}) {
    return {
      ...row.cast<String, dynamic>(),
      'id': switch (row['id']) {
        final String id when isUuidV7(id) => id,
        _ => uuidV7(),
      },
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

/// A library body as a student's copy takes it. Its sessions are filed nowhere,
/// since a folder is the coach's own and no student has it, and join as the copy
/// does rather than when the coach's did. A session with no `order` keeps its
/// place in the list: the ids a copy gets don't sort the way the document reads.
Map<String, dynamic> forCopy(Map<String, dynamic> body) {
  const coachesOwn = {'folderId', 'joined'};
  Map<String, dynamic> session(int index, Map row) => {
    'order': index,
    for (final MapEntry(:key, :value) in row.cast<String, dynamic>().entries)
      if (!coachesOwn.contains(key)) key: value,
  };

  return {
    ...body,
    if (body['sessions'] case final List sessions)
      'sessions': [
        for (final (index, each) in sessions.indexed)
          switch (each) {
            final Map row => session(index, row),
            final other => other,
          },
      ],
  };
}

/// A session as a whole replacement: every key a partial update reads as "keep
/// what's stored" is said, so one a snapshot or a library version leaves out
/// clears what's there instead of surviving it.
Map<String, dynamic> wholly(Map<String, dynamic> session) {
  Map<String, dynamic> set(Map row) => {'target': null, ...row.cast<String, dynamic>()};
  Map<String, dynamic> exercise(Map row) => {
    'rest': null,
    'superset': null,
    'pattern': null,
    'totalReps': null,
    ...row.cast<String, dynamic>(),
    if (row['sets'] case final List sets)
      'sets': [
        for (final each in sets)
          switch (each) {
            final Map row => set(row),
            final other => other,
          },
      ],
  };

  return {
    'note': null,
    ...session,
    if (session['exercises'] case final List exercises)
      'exercises': [
        for (final each in exercises)
          switch (each) {
            final Map row => exercise(row),
            final other => other,
          },
      ],
  };
}

/// What a copy of [body] needs: [exercises] for ids the student has an answer to,
/// and a new v7 for the rest. Anything else would read as no link on a workout or a
/// skip. [known] is what an earlier send or update already chose for the copy's
/// rows; an exercise goes by [exercises], which already prefers the one [known]
/// names while the student still has it. Ids compare whatever their case, as
/// Postgres does, so one id written two ways stays one.
Map<String, String> copyIds(
  Map<String, dynamic> body, {
  required Map<String, String> exercises,
  Map<String, String> known = const {},
}) {
  String? lookup(Map<String, String> ids, String id) => ids[id] ?? ids[id.toLowerCase()];
  final minted = <String, String>{};
  return {
    for (final id in idsIn(body))
      id: lookup(exercises, id) ?? lookup(known, id) ?? minted.putIfAbsent(id.toLowerCase(), uuidV7),
  };
}
