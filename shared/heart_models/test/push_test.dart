import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

import 'wire.dart';

void main() {
  group('PushSettings', () {
    final settings = PushSettings(
      topics: [
        PushSetting(
          topic: 'coaching.message',
          group: 'coaching',
          name: 'Messages',
          description: 'When someone writes to you',
          delivery: 'off',
          options: ['instant', 'off'],
        ),
      ],
      forPeople: [(topic: 'coaching.workout_digest', connectionId: 'c', delivery: 'off')],
    );

    test('round-trips', () => expectRoundTrip(settings, PushSettings.fromJson));

    // the body `GET /push/settings` answers in api/test/routes/push_test.dart
    test('reads the body the API sends', () {
      final read = PushSettings.fromJson({
        'topics': [
          {
            'topic': 'coaching.workout_digest',
            'group': 'coaching',
            'name': 'Workouts',
            'description': 'A daily round-up',
            'delivery': 'daily',
            'options': ['daily', 'off'],
          },
        ],
        'forPeople': [
          {'topic': 'coaching.workout_digest', 'connectionId': 'c', 'delivery': 'off'},
          {'topic': 'coaching.message', 'connectionId': null, 'delivery': 'off'},
        ],
      });
      expect(read.topics.single.options, ['daily', 'off']);
      expect(read.forPeople, [
        (topic: 'coaching.workout_digest', connectionId: 'c', delivery: 'off'),
        (topic: 'coaching.message', connectionId: null, delivery: 'off'),
      ]);
    });

    test('a delivery word this build has never heard of is carried', () {
      final read = PushSettings.fromJson({
        'topics': [
          {
            ...settings.topics.single.toMap(),
            'delivery': 'weekly',
            'options': ['weekly', 'off'],
          },
        ],
      });
      expect(read.topics.single.delivery, 'weekly');
      expect(read.forPeople, isEmpty);
    });

    test('a topic it cannot read leaves the rest', () {
      final read = PushSettings.fromJson({
        'topics': [
          {'topic': 'coaching.message', 'options': 3},
          settings.topics.single.toMap(),
        ],
      });
      expect(read.topics.single.topic, 'coaching.message');
    });
  });
}
