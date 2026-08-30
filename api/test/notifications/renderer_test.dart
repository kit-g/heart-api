import 'package:heart/notifications/renderer.dart';
import 'package:test/test.dart';

void main() {
  group('snippetize', () {
    test('passes short strings through unchanged', () {
      expect(snippetize('short'), 'short');
    });

    test('truncates with horizontal ellipsis at maxLength', () {
      final s = 'x' * 250;
      final out = snippetize(s);
      expect(out.length, 201); // 200 chars + 1 ellipsis
      expect(out.endsWith('…'), isTrue);
    });

    test('boundary: exact maxLength keeps the string intact', () {
      final s = 'x' * 200;
      expect(snippetize(s), s);
    });
  });

  group('renderTitle', () {
    test('renders en template with author interpolation', () {
      final out = renderTitle(
        locale: 'en',
        eventType: 'comment.created',
        variant: 'workout',
        args: {'author': 'Sarah'},
      );
      expect(out, 'Sarah: new comment on your workout');
    });

    test('renders ru template', () {
      final out = renderTitle(
        locale: 'ru',
        eventType: 'comment.created',
        variant: 'workout_exercise',
        args: {'author': 'Сара'},
      );
      expect(out, 'Сара: новый комментарий к вашему упражнению');
    });

    test('falls back to default locale on unknown locale', () {
      final out = renderTitle(
        locale: 'de',
        eventType: 'comment.created',
        variant: 'workout',
        args: {'author': 'Sarah'},
        defaultLocale: 'en',
      );
      expect(out, 'Sarah: new comment on your workout');
    });

    test('a regional locale without templates falls back to its base language', () {
      final out = renderTitle(
        locale: 'fr_CA',
        eventType: 'comment.created',
        variant: 'workout',
        args: {'author': 'Sarah'},
        defaultLocale: 'en',
      );
      expect(out, 'Sarah : nouveau commentaire sur votre entraînement');
    });

    test('returns the variant key when neither variant nor fallback exists', () {
      final out = renderTitle(
        locale: 'en',
        eventType: 'unknown.event',
        variant: 'workout',
        args: const {},
      );
      expect(out, 'workout');
    });
  });
}
