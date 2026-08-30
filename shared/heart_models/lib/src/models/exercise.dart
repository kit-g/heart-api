import 'misc.dart';
import 'uuid.dart';

abstract interface class ExerciseFilter {
  String get value;
}

enum Category implements ExerciseFilter {
  weightedBodyWeight('Weighted Body Weight'),
  assistedBodyWeight('Assisted Body Weight'),
  repsOnly('Reps Only'),
  cardio('Cardio'),
  duration('Duration'),
  machine('Machine'),
  dumbbell('Dumbbell'),
  barbell('Barbell');

  @override
  final String value;

  new(this.value);

  factory fromString(String v) {
    return switch (v) {
      'Weighted Body Weight' => weightedBodyWeight,
      'Assisted Body Weight' => assistedBodyWeight,
      'Reps Only' => repsOnly,
      'Cardio' => cardio,
      'Duration' => duration,
      'Machine' => machine,
      'Dumbbell' => dumbbell,
      'Barbell' => barbell,
      _ => throw ArgumentError('Invalid value for Category: $v'),
    };
  }

  @override
  String toString() => value;

  bool get _isWeightCategory {
    return [weightedBodyWeight, machine, dumbbell, barbell].any((each) => each == this);
  }

  bool canSwitchTo(Category other) {
    return _isWeightCategory && other._isWeightCategory;
  }
}

enum Target implements ExerciseFilter {
  core('Core'),
  arms('Arms'),
  back('Back'),
  chest('Chest'),
  legs('Legs'),
  shoulder('Shoulders'),
  other('Other'),
  olympic('Olympic'),
  fullBody('Full Body'),
  cardio('Cardio');

  @override
  final String value;

  new(this.value);

  factory fromString(String v) {
    return switch (v) {
      'Core' => core,
      'Arms' => arms,
      'Back' => back,
      'Chest' => chest,
      'Legs' => legs,
      'Shoulders' => shoulder,
      'Other' => other,
      'Olympic' => olympic,
      'Full Body' => fullBody,
      'Cardio' => cardio,
      _ => throw ArgumentError('Invalid value for Target: $v'),
    };
  }

  String get icon {
    return switch (this) {
      core => '🏋️',
      arms => '💪',
      back => '🦾',
      chest => '🏋️‍♀️',
      legs => '🦵',
      shoulder => '🤷‍♀️',
      other => '❓',
      olympic => '🏅',
      fullBody => '🤸‍♀️',
      cardio => '❤️',
    };
  }

  @override
  String toString() => value;
}

/// Compressive load carried by the spine.
///
/// Declared in ascending order so [index] comparisons are meaningful — that is
/// what makes "nothing heavier than moderate" expressible as [atMost].
enum AxialLoad {
  none('none'),
  low('low'),
  moderate('moderate'),
  high('high');

  final String value;

  new(this.value);

  factory fromString(String v) {
    return switch (v) {
      'none' => none,
      'low' => low,
      'moderate' => moderate,
      'high' => high,
      _ => throw ArgumentError('Invalid value for AxialLoad: $v'),
    };
  }

  /// True when this load is no heavier than [limit].
  bool atMost(AxialLoad limit) => index <= limit.index;

  @override
  String toString() => value;
}

/// How much the movement path is constrained.
enum Stability {
  free('free'),
  supported('supported'),
  machine('machine');

  final String value;

  new(this.value);

  factory fromString(String v) {
    return switch (v) {
      'free' => free,
      'supported' => supported,
      'machine' => machine,
      _ => throw ArgumentError('Invalid value for Stability: $v'),
    };
  }

  @override
  String toString() => value;
}

/// Joint loading from ground contact or ballistic deceleration.
enum Impact {
  none('none'),
  low('low'),
  high('high');

  final String value;

  new(this.value);

  factory fromString(String v) {
    return switch (v) {
      'none' => none,
      'low' => low,
      'high' => high,
      _ => throw ArgumentError('Invalid value for Impact: $v'),
    };
  }

  bool atMost(Impact limit) => index <= limit.index;

  @override
  String toString() => value;
}

/// Technical demand before the movement can be loaded safely.
enum SkillLevel {
  low('low'),
  moderate('moderate'),
  high('high');

  final String value;

  new(this.value);

  factory fromString(String v) {
    return switch (v) {
      'low' => low,
      'moderate' => moderate,
      'high' => high,
      _ => throw ArgumentError('Invalid value for SkillLevel: $v'),
    };
  }

  bool atMost(SkillLevel limit) => index <= limit.index;

  @override
  String toString() => value;
}

/// Movement pattern and objective load attributes for an exercise.
///
/// Two exercises are mutually replaceable when they share a [groups] entry —
/// see [sharesPatternWith]. Everything else here is a fact about the movement,
/// never a recommendation: a lifter protecting their back filters on
/// [AxialLoad], and the library stays free of per-concern policy flags.
///
/// [groups] is deliberately untyped. The vocabulary is enumerated in
/// `content/exercise_library_schema.json`, so content can add a pattern without
/// waiting on an app release.
///
/// Only [fromJson]/[toMap] exist, with no row pair: the snake_case convention
/// governs column names, not the contents of a jsonb blob, so
/// `exercises.movement` is stored camelCased by scripts/library_locales.py and
/// read paths ship it verbatim. Storage and wire are the same shape.
abstract interface class Movement implements Model {
  Iterable<String> get groups;

  AxialLoad get axialLoad;

  Stability get stability;

  bool get unilateral;

  Impact get impact;

  SkillLevel get skill;

  bool get isEmpty;

  /// True when [other] trains at least one of the same movement patterns, and
  /// so is a candidate substitution.
  bool sharesPatternWith(Movement other);

  factory fromJson(Map json) = _Movement.fromJson;

  factory empty() {
    return const _Movement(
      groups: [],
      axialLoad: .none,
      stability: .free,
      unilateral: false,
      impact: .none,
      skill: .low,
    );
  }
}

class _Movement implements Movement {
  @override
  final List<String> groups;
  @override
  final AxialLoad axialLoad;
  @override
  final Stability stability;
  @override
  final bool unilateral;
  @override
  final Impact impact;
  @override
  final SkillLevel skill;

  const new({
    required this.groups,
    required this.axialLoad,
    required this.stability,
    required this.unilateral,
    required this.impact,
    required this.skill,
  });

  /// Absent keys fall back to the schema defaults; a present but unrecognised
  /// value throws, so bad content fails loudly instead of silently reading as
  /// "unloaded".
  factory fromJson(Map json) {
    return _Movement(
      groups: switch (json['groups']) {
        List l => l.cast<String>(),
        _ => [],
      },
      axialLoad: switch (json['axialLoad']) {
        String s => AxialLoad.fromString(s),
        _ => .none,
      },
      stability: switch (json['stability']) {
        String s => Stability.fromString(s),
        _ => .free,
      },
      unilateral: switch (json['unilateral']) {
        bool b => b,
        1 => true, // sqlite, if the blob is ever flattened
        _ => false,
      },
      impact: switch (json['impact']) {
        String s => Impact.fromString(s),
        _ => .none,
      },
      skill: switch (json['skill']) {
        String s => SkillLevel.fromString(s),
        _ => .low,
      },
    );
  }

  @override
  Map<String, dynamic> toMap() {
    return {
      'groups': groups,
      'axialLoad': axialLoad.value,
      'stability': stability.value,
      'unilateral': unilateral,
      'impact': impact.value,
      'skill': skill.value,
    };
  }

  @override
  bool get isEmpty => groups.isEmpty;

  @override
  bool sharesPatternWith(Movement other) {
    return groups.any(other.groups.contains);
  }
}

/// Canonical activity type a session of an exercise is written to the platform
/// health store as (HealthKit / Health Connect).
///
/// The vocabulary is deliberately platform-neutral: the client maps each value
/// to the per-platform enum spelling (`swimming` is `SWIMMING` on iOS and
/// `SWIMMING_POOL` on Android). Session-level activities — cross-training,
/// mixed cardio — are not here on purpose: they describe a workout mixing
/// several exercises and the client derives them.
enum HealthActivity {
  strength('strength'),
  cycling('cycling'),
  cyclingIndoor('cyclingIndoor'),
  elliptical('elliptical'),
  hiking('hiking'),
  rowing('rowing'),
  running('running'),
  runningTreadmill('runningTreadmill'),
  skating('skating'),
  skiing('skiing'),
  snowboarding('snowboarding'),
  swimming('swimming'),
  walking('walking'),
  climbing('climbing'),
  coreTraining('coreTraining'),
  flexibility('flexibility'),
  yoga('yoga'),
  cardioDance('cardioDance'),
  highIntensity('highIntensity'),
  jumpRope('jumpRope'),
  other('other');

  final String value;

  new(this.value);

  factory fromString(String v) {
    return switch (v) {
      'strength' => strength,
      'cycling' => cycling,
      'cyclingIndoor' => cyclingIndoor,
      'elliptical' => elliptical,
      'hiking' => hiking,
      'rowing' => rowing,
      'running' => running,
      'runningTreadmill' => runningTreadmill,
      'skating' => skating,
      'skiing' => skiing,
      'snowboarding' => snowboarding,
      'swimming' => swimming,
      'walking' => walking,
      'climbing' => climbing,
      'coreTraining' => coreTraining,
      'flexibility' => flexibility,
      'yoga' => yoga,
      'cardioDance' => cardioDance,
      'highIntensity' => highIntensity,
      'jumpRope' => jumpRope,
      'other' => other,
      _ => throw ArgumentError('Invalid value for HealthActivity: $v'),
    };
  }

  @override
  String toString() => value;
}

/// How the exercise is represented in the platform health store.
///
/// Optional like [Movement], and absent is the common case: most of the
/// library is lifting, and a user-created exercise has no library entry at
/// all. [resolve] carries the fallback, so an absent annotation is a fact
/// about the library, never a hole in the activity path.
///
/// Only [fromJson]/[toMap] exist for the same reason as [Movement]:
/// `exercises.health` is stored camelCased by scripts/library_locales.py and
/// read paths ship the blob verbatim.
abstract interface class Health implements Model {
  HealthActivity? get activity;

  bool get isEmpty;

  /// The activity a session of an exercise in [category] is written as.
  ///
  /// An explicit annotation wins; otherwise `Cardio`/`Duration` resolve to
  /// [HealthActivity.other] and everything else to [HealthActivity.strength].
  /// The category arm is load-bearing: a custom cardio exercise must never
  /// land in the user's health record as strength training.
  HealthActivity resolve(Category category);

  factory fromJson(Map json) = _Health.fromJson;

  factory empty() {
    return const _Health(activity: null);
  }
}

class _Health implements Health {
  @override
  final HealthActivity? activity;

  const new({required this.activity});

  /// An absent key is the annotated-nowhere common case; a present but
  /// unrecognised value throws, so bad content fails loudly instead of
  /// silently mislabeling a workout in the user's own health record.
  factory fromJson(Map json) {
    return _Health(
      activity: switch (json['activity']) {
        String s => HealthActivity.fromString(s),
        _ => null,
      },
    );
  }

  @override
  Map<String, dynamic> toMap() {
    return {
      'activity': ?activity?.value,
    };
  }

  @override
  bool get isEmpty => activity == null;

  @override
  HealthActivity resolve(Category category) {
    return activity ??
        switch (category) {
          .cardio || .duration => .other,
          _ => .strength,
        };
  }
}

abstract interface class MuscleTag implements Model {
  Iterable<String>? get ids;

  Iterable<String>? get groups;

  bool get isEmpty;

  factory fromJson(Map json) {
    return _MuscleTag(
      ids: switch (json['ids']) {
        List l => l.cast<String>(),
        _ => [],
      },
      groups: switch (json['groups']) {
        List l => l.cast<String>(),
        _ => [],
      },
    );
  }

  factory empty() {
    return const _MuscleTag(ids: [], groups: []);
  }
}

class _MuscleTag implements MuscleTag {
  @override
  final List<String>? ids;
  @override
  final List<String>? groups;

  const new({
    required this.ids,
    required this.groups,
  });

  @override
  Map<String, dynamic> toMap() {
    return {
      'ids': ids,
      'groups': groups,
    };
  }

  @override
  bool get isEmpty => (ids?.isEmpty ?? true) && (groups?.isEmpty ?? true);
}

abstract interface class MuscleTagging implements Model {
  MuscleTag get primary;

  MuscleTag? get secondary;

  bool get isEmpty;

  factory fromJson(Map json) {
    return _MuscleTagging(
      primary: MuscleTag.fromJson(json['primary'] ?? {}),
      secondary: switch (json) {
        {'secondary': Map m} => MuscleTag.fromJson(m),
        _ => null,
      },
    );
  }

  factory empty() {
    return _MuscleTagging(primary: MuscleTag.empty(), secondary: null);
  }
}

class _MuscleTagging implements MuscleTagging {
  @override
  final MuscleTag primary;
  @override
  final MuscleTag? secondary;

  const new({
    required this.primary,
    required this.secondary,
  });

  @override
  Map<String, dynamic> toMap() {
    return {
      'primary': primary.toMap(),
      if (secondary != null) 'secondary': secondary!.toMap(),
    };
  }

  @override
  bool get isEmpty => primary.isEmpty && (secondary?.isEmpty ?? true);
}

abstract interface class Exercise implements Searchable, Model, Comparable<Exercise> {
  /// The identity: the server row's uuid, or the client-minted UUIDv7 for a
  /// custom exercise created offline (the server persists that id on sync).
  String get id;

  /// The env-stable content slug (`bench-press-barbell`) for library
  /// exercises; null for user-created ones. A content/fixture handle, not a
  /// wire reference — saves go by [id].
  String? get key;

  /// Localized display copy for the locale the library was fetched under —
  /// never an identifier.
  String get name;

  Category get category;

  Target get target;

  Asset? get asset;

  Asset? get thumbnail;

  String? get instructions;

  /// Whether a human has reviewed this exercise's copy ([name] and
  /// [instructions]) for the served locale.
  ///
  /// `false` marks machine-authored library copy — the client labels it as
  /// such, in the spirit of being explicit about provenance. `null` is "no
  /// stance": the exercise carries no library-managed copy (user-created
  /// exercises), so there is nothing to label.
  bool? get validated;

  bool get hasInfo;

  bool get isMine;

  bool get isArchived;

  MuscleTagging get muscles;

  /// Movement pattern and load attributes. Empty when the library offers no
  /// substitute for this exercise (and for user-created exercises).
  Movement get movement;

  /// Health store representation. Empty for most exercises (and all
  /// user-created ones); read the activity through [activity], never through
  /// the exercise name — [name] is localized copy.
  Health get health;

  /// The activity a session of this exercise is written to the health store
  /// as, annotation or [Health.resolve] fallback.
  HealthActivity get activity;

  /// The requesting user's preferred display unit for this exercise.
  /// `null` falls back to the user's global setting.
  MeasurementUnit? get unitSystem;

  /// The requesting user's preferred rest timer (seconds) for this exercise.
  int? get restTimer;

  factory fromJson(Map json) = _Exercise.fromJson;

  factory({
    required String name,
    required Category category,
    required Target target,
    String? instructions,
    bool? isMine,
    MuscleTagging? tags,
    Movement? movement,
    Health? health,
  }) {
    assert(name.isNotEmpty, 'Cannot have an empty name');
    return _Exercise(
      id: uuidV7(),
      name: name,
      category: category,
      target: target,
      instructions: instructions,
      isMine: isMine ?? false,
      muscles: tags ?? MuscleTagging.empty(),
      movement: movement ?? Movement.empty(),
      health: health ?? Health.empty(),
    );
  }

  bool fits(Iterable<ExerciseFilter> filters);

  Exercise copyWith({
    Category? category,
    Target? target,
    Asset? asset,
    Asset? thumbnail,
    bool? isMine,
    String? instructions,
    bool? isArchived,
    MuscleTagging? tags,
    Movement? movement,
    Health? health,
    MeasurementUnit? unitSystem,
  });
}

class _Exercise implements Exercise {
  @override
  final String id;
  @override
  final String? key;
  @override
  final String name;
  @override
  final Category category;
  @override
  final Target target;
  @override
  final Asset? asset;
  @override
  final Asset? thumbnail;
  @override
  final String? instructions;
  @override
  final bool? validated;
  @override
  final bool isMine;
  @override
  final bool isArchived;
  @override
  final MuscleTagging muscles;
  @override
  final Movement movement;
  @override
  final Health health;
  @override
  final MeasurementUnit? unitSystem;
  @override
  final int? restTimer;

  const new({
    required this.id,
    this.key,
    required this.name,
    required this.category,
    required this.target,
    this.asset,
    this.thumbnail,
    this.instructions,
    this.validated,
    this.isMine = false,
    this.isArchived = false,
    required this.muscles,
    required this.movement,
    required this.health,
    this.unitSystem,
    this.restTimer,
  });

  factory fromJson(Map json) {
    return _Exercise(
      id: switch (json['id']) {
        final String id => id,
        _ => throw ArgumentError.value(json, 'json', 'an exercise payload must carry its id'),
      },
      key: json['key'],
      name: json['name'] ?? json['exercise'],
      category: Category.fromString(json['category']),
      target: Target.fromString(json['target']),
      asset: switch (json['asset']) {
        // comes from remote
        Map asset && {'link': String link} => (link: link, width: asset['width'], height: asset['height']),
        // comes from local SQLite
        String link => (link: link, width: json['assetWidth'], height: json['assetHeight']) as Asset,
        _ => null,
      },
      thumbnail: switch (json['thumbnail']) {
        // comes from remote
        Map thumb && {'link': String link} => (link: link, width: thumb['width'], height: thumb['height']),
        // comes from local SQLite
        String link => (link: link, width: json['thumbnailWidth'], height: json['thumbnailHeight']) as Asset,
        _ => null,
      },
      instructions: json['instructions'],
      validated: switch (json['validated']) {
        bool validated => validated, // API
        1 => true, // local
        0 => false, // local
        _ => null, // no library-managed copy
      },
      isMine: switch (json['own']) {
        bool mine => mine, // API
        1 => true, // local
        _ => false, // local
      },
      isArchived: switch (json['archived']) {
        bool archived => archived, // API
        1 => true, // local
        _ => false, // local
      },
      muscles: MuscleTagging.fromJson(json['muscles'] ?? {}),
      movement: Movement.fromJson(json['movement'] ?? {}),
      health: Health.fromJson(json['health'] ?? {}),
      unitSystem: switch (json['unit_system'] ?? json['unitSystem']) {
        String s => MeasurementUnit.fromString(s),
        _ => null,
      },
      restTimer: switch (json['rest_timer'] ?? json['restTimer']) {
        int s => s,
        _ => null,
      },
    );
  }

  @override
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'key': ?key,
      'category': category.value,
      'name': name,
      'target': target.value,
      if (instructions != null) 'instructions': instructions,
      if (validated case bool validated) 'validated': validated ? 1 : 0,
      if (asset case Asset asset) ...{
        'asset': asset.link,
        'assetHeight': asset.height,
        'assetWidth': asset.width,
      },
      if (thumbnail case Asset thumbnail) ...{
        'thumbnail': thumbnail.link,
        'thumbnailHeight': thumbnail.height,
        'thumbnailWidth': thumbnail.width,
      },
      'own': isMine ? 1 : 0,
      'archived': isArchived ? 1 : 0,
      if (!muscles.isEmpty) 'muscles': muscles.toMap(),
      if (!movement.isEmpty) 'movement': movement.toMap(),
      if (!health.isEmpty) 'health': health.toMap(),
      'unitSystem': ?unitSystem?.name,
      'restTimer': ?restTimer,
    };
  }

  @override
  String toString() => name;

  @override
  bool contains(String query) {
    if (query.isEmpty) return true;

    final queryWords = query.normalized().split(RegExp(r'\s+')).map((w) => w.trim());
    final words = [
      ...name.normalized().split(RegExp(r'[\s()]+')),
      // the slug still matches the canonical English wording when the display
      // name is localized
      ...?key?.split('-'),
    ].map((w) => w.trim());

    return queryWords.every((queryWord) => words.any((word) => word.contains(queryWord)));
  }

  /// The uuid is the identity; [name] is localized display copy and two
  /// locales' views of the same exercise must compare equal.
  @override
  bool operator ==(Object other) {
    return other is Exercise && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  bool fits(Iterable<ExerciseFilter> filters) {
    final categories = filters.whereType<Category>();
    final targets = filters.whereType<Target>();

    final categoryMatches = categories.isEmpty || categories.contains(category);
    final targetMatches = targets.isEmpty || targets.contains(target);

    return categoryMatches && targetMatches;
  }

  @override
  bool get hasInfo => [asset, instructions, thumbnail].any((attr) => attr != null);

  @override
  HealthActivity get activity => health.resolve(category);

  @override
  int compareTo(Exercise other) {
    return name.toLowerCase().compareTo(other.name.toLowerCase());
  }

  @override
  Exercise copyWith({
    Category? category,
    Target? target,
    Asset? asset,
    Asset? thumbnail,
    bool? isMine,
    String? instructions,
    bool? isArchived,
    MuscleTagging? tags,
    Movement? movement,
    Health? health,
    MeasurementUnit? unitSystem,
    int? restTimer,
  }) {
    return _Exercise(
      id: id,
      key: key,
      name: name,
      category: category ?? this.category,
      target: target ?? this.target,
      asset: asset ?? this.asset,
      thumbnail: thumbnail ?? this.thumbnail,
      isMine: isMine ?? this.isMine,
      instructions: instructions ?? this.instructions,
      // library-owned provenance flag: carried, never client-mutated
      validated: validated,
      isArchived: isArchived ?? this.isArchived,
      muscles: tags ?? muscles,
      movement: movement ?? this.movement,
      health: health ?? this.health,
      unitSystem: unitSystem ?? this.unitSystem,
      restTimer: restTimer ?? this.restTimer,
    );
  }
}

typedef ExerciseId = String;
typedef Asset = ({String link, int? width, int? height});

extension on String {
  /// Strip dashes and other common symbols to make search more forgiving.
  /// Keeps letters (any script — display names are localized), numbers, and
  /// spaces.
  String normalized() {
    return toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), '');
  }
}
