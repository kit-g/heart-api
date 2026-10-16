import 'package:heart_models/heart_models.dart';

/// The free program library as the CDN serves it (`static/programs`,
/// `docs/2026-10-14.program-library.md`): the one copy the app, `/me` and MCP
/// all read (heart-api#259).
abstract interface class ProgramLibrary {
  /// The rendered file, or null while none is published.
  Future<Map<String, dynamic>?> read();
}

/// The library read in one locale: copy picked from its translations, falling
/// back to English, and exercises named the way the caller's library names
/// them. Read tolerantly, as the app reads it: a key this server doesn't know
/// is passed over, never an error.
final class LibraryView {
  final Map<String, dynamic> _content;

  /// The caller's locale, as `Request.locale` picks it: `es`, `en_CA`.
  final String locale;

  /// Library exercise keys to the caller's exercises: `id` and `name`.
  final Map<String, ({String id, String name})> exercises;

  const new(this._content, {required this.locale, required this.exercises});

  Iterable<Map<String, dynamic>> get _programs =>
      (_content['programs'] as List? ?? const []).whereType<Map<String, dynamic>>();

  Map<String, dynamic> get _sources => (_content['sources'] as Map?)?.cast<String, dynamic>() ?? const {};

  Map<String, dynamic> get _safety => (_content['safety'] as Map?)?.cast<String, dynamic>() ?? const {};

  /// Every program with the facts that help choose one.
  List<Map<String, dynamic>> list() => [for (final program in _programs) _summary(program)];

  /// One program in full, or null when the library has no [key].
  Map<String, dynamic>? program(String key) {
    final program = _byKey(key);
    if (program == null) return null;
    final sessions = (program['sessions'] as List? ?? const []).whereType<Map>().toList();
    final sessionNames = {for (final session in sessions) '${session['id']}': _named(session)};
    final slots = {
      for (final session in sessions)
        for (final exercise in (session['exercises'] as List? ?? const []).whereType<Map>())
          '${exercise['id']}': session,
    };
    // a rule keyed by a session exercise's id is that occurrence's own, shown
    // on it; the rest are by exercise key
    final all = (program['rules'] as Map?)?.cast<String, dynamic>() ?? const {};
    final rules = {
      for (final MapEntry(:key, :value) in all.entries)
        if (!slots.containsKey(key)) key: value,
    };
    // every exercise key the view names: in sessions, rules and ladders
    final used = <String>{
      ...rules.keys,
      for (final rule in all.values.whereType<Map>()) ...?(rule['rungs'] as List?)?.whereType<String>(),
      for (final session in sessions)
        for (final exercise in (session['exercises'] as List? ?? const []).whereType<Map>()) ...[
          if (exercise['exercise'] case {'key': final String key}) key,
          for (final set in (exercise['sets'] as List? ?? const []).whereType<Map>())
            if (set['target'] case {'of': final String of}) of,
        ],
    };
    final view = {
      ..._summary(program),
      'week': ?_pick(program['week']),
      'grows': ?_pick(program['grows']),
      'misses': ?_pick(program['misses']),
      'rules': rules,
      if (program['deload'] case final Map deload) 'deload': deload,
      if (program['phases'] case final List phases)
        'phases': [
          for (final phase in phases.whereType<Map>())
            {
              'name': ?_pick(phase['name']),
              'sessions': [for (final id in phase['sessions'] as List? ?? const []) sessionNames[id] ?? id],
              'cycles': ?phase['cycles'],
            },
        ],
      if (program['tests'] case final Map tests)
        'tests': {for (final MapEntry(:key, :value) in tests.entries) sessionNames[key] ?? key: value},
      'sessions': [
        for (final session in sessions)
          {
            'name': _named(session),
            'note': ?_named(session, field: 'note', translations: 'noteI18n'),
            'exercises': [
              for (final exercise in (session['exercises'] as List? ?? const []).whereType<Map>())
                {
                  if (exercise['exercise'] case {'key': final String key}) ...{
                    'exercise': key,
                    'name': exercises[key]?.name ?? key,
                  },
                  for (final field in const ['rest', 'superset', 'pattern', 'totalReps'])
                    if (exercise[field] case final Object value) field: value,
                  'rule': ?all[exercise['id']],
                  'sets': [
                    for (final set in (exercise['sets'] as List? ?? const []).whereType<Map>())
                      {
                        if (set['set_type'] case final String type when type != 'normal') 'setType': type,
                        // the occurrence a share is of, by its session's name
                        if (set['target'] case final Map target)
                          'target': {
                            ...target,
                            if (target['ofSlot'] case final String slot)
                              'ofSlot': switch (slots[slot]) {
                                final Map session => _named(session),
                                null => slot,
                              },
                          },
                      },
                  ],
                },
            ],
          },
      ],
      'research': [for (final claim in _claims(program)) _claim(claim, sessions: sessionNames)],
      'sources': _cited(program),
      'safety': [
        for (final key in program['safety'] as List? ?? const [])
          if (_safety[key] case final Map note) ?_pick(note['text']),
      ],
      'next': [
        for (final key in program['next'] as List? ?? const [])
          if (_byKey('$key') case final Map next) {'key': key, 'name': _named(next)},
      ],
    };
    return {
      ...view,
      // what every exercise key above is called in the caller's library
      'exercises': {for (final key in used) key: exercises[key]?.name ?? key},
    };
  }

  /// The research behind [program], a user's copy of the library program its
  /// [Program.source] names, or null when it names none the library has. Each
  /// claim is anchored to the copy: a rule by the exercise's id, a session by
  /// the copy's session at the same place in [sessions], and an exercise when
  /// that session has the same exercise at the same place. A claim whose
  /// anchors no longer find their part, because the user changed it, sits on
  /// the program.
  Map<String, dynamic>? researchFor(Program program, List<Template?> sessions) {
    final library = switch (program.source) {
      final String key => _byKey(key),
      null => null,
    };
    if (library == null) return null;
    final ours = (library['sessions'] as List? ?? const []).whereType<Map>().toList();
    final placeOf = {for (final (index, session) in ours.indexed) '${session['id']}': index};

    Map<String, dynamic>? anchor(Map about) {
      switch (about) {
        case {'on': 'rule', 'exercise': final String key}:
          return switch (exercises[key]) {
            (:final id, name: _) => {'on': 'rule', 'exercise': id},
            null => null,
          };
        case {'on': 'session', 'session': final String id}:
          return switch (placeOf[id]) {
            final int at when at < program.sessions.length => {'on': 'session', 'session': program.sessions[at]},
            _ => null,
          };
        case {'on': 'exercise', 'session': final String id, 'exercise': final String slot}:
          final at = placeOf[id];
          if (at == null || at >= sessions.length) return null;
          final copy = sessions[at];
          final theirs = (ours[at]['exercises'] as List? ?? const []).whereType<Map>().toList();
          final index = theirs.indexWhere((exercise) => exercise['id'] == slot);
          if (copy == null || index < 0 || index >= copy.length) return null;
          final mine = copy.elementAt(index);
          final key = (theirs[index]['exercise'] as Map?)?['key'];
          if (exercises[key]?.id != mine.exercise.id) return null;
          return {'on': 'exercise', 'session': copy.id, 'exercise': mine.id};
        case {'on': final String part} when part != 'rule' && part != 'session' && part != 'exercise':
          return {'on': part};
        default:
          return null;
      }
    }

    return {
      'key': library['key'],
      'claims': [
        for (final claim in _claims(library))
          {
            'text': ?_pick(claim['text']),
            'sources': [...?(claim['sources'] as List?)?.whereType<String>()],
            'about': switch ([
              for (final about in (claim['about'] as List? ?? const []).whereType<Map>()) ?anchor(about),
            ]) {
              final List<Map<String, dynamic>> anchors when anchors.isNotEmpty => anchors,
              _ => const [
                {'on': 'program'},
              ],
            },
          },
      ],
      'sources': _cited(library),
    };
  }

  Map<String, dynamic>? _byKey(String key) => _programs.where((program) => program['key'] == key).firstOrNull;

  Map<String, dynamic> _summary(Map program) {
    return {
      'key': program['key'],
      'name': _named(program),
      'note': ?_named(program, field: 'note', translations: 'noteI18n'),
      'audience': ?program['audience'],
      'equipment': ?program['equipment'],
      'perWeek': ?program['perWeek'],
      'minutes': ?program['minutes'],
      'weeks': ?program['weeks'],
      // the oldest app build that can run it; none is any that reads the library
      'minApp': ?program['minApp'],
      'who': ?_pick(program['who']),
    };
  }

  Iterable<Map> _claims(Map program) => (program['why'] as List? ?? const []).whereType<Map>();

  /// A claim in this locale, its anchors as the library writes them, sessions
  /// by name.
  Map<String, dynamic> _claim(Map claim, {required Map<String, String?> sessions}) {
    return {
      'text': ?_pick(claim['text']),
      'sources': [...?(claim['sources'] as List?)?.whereType<String>()],
      'about': [
        for (final about in (claim['about'] as List? ?? const []).whereType<Map>())
          {
            for (final MapEntry(:key, :value) in about.entries)
              '$key': key == 'session' ? sessions[value] ?? value : value,
          },
      ],
    };
  }

  /// The sources [program] cites, by key, in this locale.
  Map<String, dynamic> _cited(Map program) {
    return {
      for (final key in program['sources'] as List? ?? const [])
        if (_sources[key] case final Map source)
          '$key': {
            'title': ?source['title'],
            'who': ?source['who'],
            'year': ?source['year'],
            'url': ?source['url'],
            'finding': ?_pick(source['finding']),
          },
    };
  }

  /// [item]'s [field] in this locale: from its [translations] map, else as
  /// written, which is English.
  String? _named(Map item, {String field = 'name', String translations = 'i18n'}) {
    final i18n = item[translations];
    return switch (i18n is Map ? _inLocale(i18n) : null) {
      final String text => text,
      _ => item[field] as String?,
    };
  }

  /// A `{en, es, …}` text in this locale, else in English.
  String? _pick(Object? texts) {
    return switch (texts) {
      final Map texts => _inLocale(texts) ?? texts['en'] as String?,
      final String text => text,
      _ => null,
    };
  }

  String? _inLocale(Map texts) {
    return switch (texts[locale] ?? texts[locale.split('_').first]) {
      final String text => text,
      _ => null,
    };
  }
}

/// A [LibraryView] read, as a response body.
final class LibraryResponse implements Model {
  final Map<String, dynamic> _body;

  const new(this._body);

  @override
  Map<String, dynamic> toMap() => _body;
}
