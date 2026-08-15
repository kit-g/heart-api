part of 'inputs.dart';

/// `GET /templates?cursor=&limit=&folder=` — the page query plus a folder filter.
///
/// `folder=<uuid>` lists that folder; the literal `folder=none` lists the
/// templates in no folder at all. Omitting it lists everything the user owns,
/// which is what the app has always received.
///
/// The cursor is a `(order, id)` pair rather than a bare id, because the listing
/// is ordered by the user's arrangement — see [OrderedCursor].
class TemplateListQuery {
  static const unfiled = 'none';

  final int limit;
  final OrderedCursor? cursor;
  final String? folderId;
  final bool unfiledOnly;

  const new _({
    required this.limit,
    required this.cursor,
    required this.folderId,
    required this.unfiledOnly,
  });

  static TemplateListQuery fromRequest(Request req) {
    final query = req.url.queryParameters;
    final page = PageQuery.fromRequest(req);
    final folder = query.stringOrNull('folder');

    return TemplateListQuery._(
      limit: page.limit,
      cursor: switch (page.cursor) {
        null => null,
        final raw => OrderedCursor.tryParse(raw) ?? (throw BadRequest(reason: 'cursor is not a valid cursor: $raw')),
      },
      folderId: folder == unfiled ? null : folder,
      unfiledOnly: folder == unfiled,
    );
  }
}

/// `POST /templates` — `{name?, order?, folderId?, exercises: [...]}`.
class TemplateCreateIn {
  final TemplateRequest request;

  const new _(this.request);

  static Future<TemplateCreateIn> fromRequest(Request req) async {
    final json = await req.json();
    return TemplateCreateIn._(
      TemplateRequest(
        userId: req.userId,
        name: json.templateName(),
        order: json.templateOrder(),
        folderId: json.folderIdOrNull(),
        exercises: json.templateExercises(),
      ),
    );
  }
}

/// `PUT /templates/:templateId` — a full replace of the template body.
///
/// Filing is three-valued and the distinction is deliberate: no `folderId` key
/// leaves the template where it is, `"folderId": null` unfiles it, and an id
/// files it there. That is what [TemplateRequest.movesFolder] carries.
class TemplateUpdateIn {
  final TemplateRequest request;

  const new _(this.request);

  static Future<TemplateUpdateIn> fromRequest(Request req) async {
    final json = await req.json();
    return TemplateUpdateIn._(
      TemplateRequest(
        userId: req.userId,
        name: json.templateName(),
        order: json.templateOrder(),
        folderId: json.folderIdOrNull(),
        movesFolder: json.containsKey('folderId'),
        exercises: json.templateExercises(),
      ),
    );
  }
}

extension on Map<String, dynamic> {
  /// Optional — an unnamed template is legal, the app shows the date instead.
  String? templateName() {
    return switch (this['name']) {
      null => null,
      final String n when n.trim().isEmpty => null,
      final String n when n.length <= 200 => n.trim(),
      _ => throw const BadRequest(reason: 'name must be a string of at most 200 chars'),
    };
  }

  int templateOrder() {
    return switch (this['order']) {
      null => 0,
      final num o => o.toInt(),
      _ => throw const BadRequest(reason: 'order must be a number'),
    };
  }

  String? folderIdOrNull() {
    return switch (this['folderId']) {
      null => null,
      final String f when f.isNotEmpty => f,
      _ => throw const BadRequest(reason: 'folderId must be a uuid string or null'),
    };
  }

  /// `exercises` may be absent or empty — an empty template is a legal thing to
  /// save while the user is still building it.
  ///
  /// Entries that are *entirely* empty are dropped rather than rejected. That is
  /// not leniency for its own sake: `WorkoutExercise.toMap()` writes `exercise`
  /// null-aware off its first set, so an exercise the user emptied in the
  /// template editor serializes as `{id, start, sets: []}` with no `exercise` at
  /// all. Rejecting those would turn "I deleted the last set" into a failed save
  /// of the whole template. An entry carrying sets but no usable name is a
  /// different thing — that is a malformed client, and it 400s.
  List<TemplateExerciseRequest> templateExercises() {
    final raw = switch (this['exercises']) {
      null => const <dynamic>[],
      final List l => l,
      _ => throw const BadRequest(reason: 'exercises must be an array'),
    };

    return [
      for (final (index, each) in raw.indexed)
        switch (each) {
          final Map m when !m.cast<String, dynamic>().isEmptyExercise => _exercise(m.cast<String, dynamic>(), index),
          final Map _ => null,
          _ => throw BadRequest(reason: 'exercises[$index] must be an object'),
        },
    ].nonNulls.toList();
  }

  /// An editor row the user emptied: nothing names an exercise and nothing was
  /// logged against it.
  bool get isEmptyExercise {
    final hasSets = switch (this['sets']) {
      final List l => l.isNotEmpty,
      _ => false,
    };
    return this['exercise'] == null && !hasSets;
  }
}

TemplateExerciseRequest _exercise(Map<String, dynamic> json, int index) {
  // The exercise arrives either as a bare name or as the full object the app
  // holds; both carry the name, which is the only part the SQL resolves on.
  final name = switch (json['exercise']) {
    final String s when s.isNotEmpty => s,
    {'name': final String n} when n.isNotEmpty => n,
    _ => throw BadRequest(
      reason: 'exercises[$index].exercise must be an exercise name or an object with one',
    ),
  };

  return TemplateExerciseRequest(
    exerciseName: name,
    order: switch (json['order']) {
      null => index,
      final num o => o.toInt(),
      _ => throw BadRequest(reason: 'exercises[$index].order must be a number'),
    },
    sets: switch (json['sets']) {
      null => const [],
      final List l => [
        for (final (setIndex, set) in l.indexed)
          switch (set) {
            final Map m => _set(m.cast<String, dynamic>(), index, setIndex),
            _ => throw BadRequest(reason: 'exercises[$index].sets[$setIndex] must be an object'),
          },
      ],
      _ => throw BadRequest(reason: 'exercises[$index].sets must be an array'),
    },
  );
}

TemplateSetRequest _set(Map<String, dynamic> json, int index, int setIndex) {
  num? measure(String field, {bool allowNegative = false}) {
    return switch (json[field]) {
      null => null,
      final num n when allowNegative || !n.isNegative => n,
      _ => throw BadRequest(reason: 'exercises[$index].sets[$setIndex].$field must be a number >= 0'),
    };
  }

  return TemplateSetRequest(
    // Weight is the one measure that can legitimately go below zero — assisted
    // movements and deficit work are expressed against bodyweight — and the
    // column has never constrained it, so this layer must not start.
    weight: measure('weight', allowNegative: true),
    reps: measure('reps'),
    duration: measure('duration'),
    distance: measure('distance'),
  );
}
