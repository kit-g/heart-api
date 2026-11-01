import 'package:heart/notifications/templates.dart';
import 'package:heart/notifications/topics.dart';
import 'package:test/test.dart';

void main() {
  test('every topic a person can choose has its words, in every language', () {
    for (final MapEntry(key: locale, value: byTopic) in notificationTemplates.entries) {
      for (final topic in PushTopic.settable) {
        final copy = byTopic[topic.key];
        expect(copy, isNotNull, reason: '$locale has no ${topic.key}');
        expect(copy!['name'], isNotNull, reason: '$locale ${topic.key}: name');
        expect(copy['description'], isNotNull, reason: '$locale ${topic.key}: description');
        final titles = copy.keys.where((key) => key != 'name' && key != 'description');
        expect(titles, isNotEmpty, reason: '$locale ${topic.key}: title');
      }
    }
  });

  // A push goes through Apple and Google. A name is all the words can hold, so
  // a message's text or a weight has nowhere to go.
  test('a push can only ever say who', () {
    final argument = RegExp(r'\{(\w+)\}');
    for (final byTopic in notificationTemplates.values) {
      for (final copy in byTopic.values) {
        for (final text in copy.values) {
          for (final match in argument.allMatches(text)) {
            expect(match.group(1), 'name');
          }
        }
      }
    }
  });

  test('a topic with options offers its own default', () {
    for (final topic in PushTopic.settable) {
      expect(topic.options, contains(topic.fallback), reason: topic.key);
    }
  });

  test('keys are what the preferences table accepts', () {
    for (final topic in PushTopic.values) {
      expect(topic.key, matches(RegExp(r'^[a-z][a-z0-9_.]{0,63}$')));
    }
  });

  group('deliveryFor', () {
    test('this person, then the topic, then the default', () {
      const topic = PushTopic.coachingMessage;
      expect(topic.deliveryFor(), 'instant');
      expect(topic.deliveryFor(forTopic: 'off'), 'off');
      expect(topic.deliveryFor(forPerson: 'instant', forTopic: 'off'), 'instant');
    });

    test('a word the topic does not offer falls back', () {
      expect(PushTopic.coachingMessage.deliveryFor(forTopic: 'weekly'), 'instant');
    });
  });
}
