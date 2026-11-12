import 'misc.dart';
import 'tolerant.dart';

/// One push topic as a settings screen draws it: the server sends the words, so
/// a build that has never heard of a topic can still show and change it.
abstract interface class PushSetting implements Model {
  String get topic;

  String get group;

  String get name;

  String get description;

  /// How it reaches this person now: `instant`, `daily`, `off`, or a word a later
  /// server adds, kept as text so this build carries it.
  String get delivery;

  /// What they can choose from.
  List<String> get options;

  /// The sides of a connection this topic can be chosen for one person from, as the
  /// reader's own role in it: `coach`, `student`, `peer`, or a word a later server
  /// adds. A coach is offered `coaching.program_received` for nobody, since it only
  /// ever reaches a student. Empty: the topic is chosen for everyone at once.
  List<String> get perPersonAs;

  factory({
    required String topic,
    required String group,
    required String name,
    required String description,
    required String delivery,
    required List<String> options,
    List<String> perPersonAs,
  }) = _PushSetting.new;

  factory fromJson(Map json) {
    return PushSetting(
      topic: json['topic'] as String,
      group: json['group'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      delivery: json['delivery'] as String,
      options: [for (final option in json['options'] as List) '$option'],
      perPersonAs: [for (final role in (json['perPersonAs'] as List?) ?? const []) '$role'],
    );
  }
}

class _PushSetting implements PushSetting {
  @override
  final String topic;
  @override
  final String group;
  @override
  final String name;
  @override
  final String description;
  @override
  final String delivery;
  @override
  final List<String> options;
  @override
  final List<String> perPersonAs;

  const new({
    required this.topic,
    required this.group,
    required this.name,
    required this.description,
    required this.delivery,
    required this.options,
    this.perPersonAs = const [],
  });

  @override
  Map<String, dynamic> toMap() {
    return {
      'topic': topic,
      'group': group,
      'name': name,
      'description': description,
      'delivery': delivery,
      'options': options,
      'perPersonAs': perPersonAs,
    };
  }
}

/// What someone said about a topic, for the whole topic or for one relationship.
typedef PushPreference = ({String topic, String? connectionId, String delivery});

/// `GET /push/settings`: every topic, and what was said for particular people.
class PushSettings implements Model {
  final List<PushSetting> topics;
  final List<PushPreference> forPeople;

  const new({required this.topics, this.forPeople = const []});

  /// A topic or a preference this build can't read is left out; the rest still show.
  factory fromJson(Map json) {
    return PushSettings(
      topics: readIndexed(json['topics'], PushSetting.fromJson).items,
      forPeople: readIndexed(
        json['forPeople'],
        (each) => (
          topic: each['topic'] as String,
          connectionId: each['connectionId'] as String?,
          delivery: each['delivery'] as String,
        ),
      ).items,
    );
  }

  @override
  Map<String, dynamic> toMap() {
    return {
      'topics': [for (final topic in topics) topic.toMap()],
      'forPeople': [
        for (final preference in forPeople)
          {
            'topic': preference.topic,
            'connectionId': preference.connectionId,
            'delivery': preference.delivery,
          },
      ],
    };
  }
}
