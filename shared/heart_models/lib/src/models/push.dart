import 'misc.dart';

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

  factory({
    required String topic,
    required String group,
    required String name,
    required String description,
    required String delivery,
    required List<String> options,
  }) = _PushSetting.new;

  factory fromJson(Map json) {
    return PushSetting(
      topic: json['topic'] as String,
      group: json['group'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      delivery: json['delivery'] as String,
      options: [for (final option in json['options'] as List) '$option'],
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

  const new({
    required this.topic,
    required this.group,
    required this.name,
    required this.description,
    required this.delivery,
    required this.options,
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
