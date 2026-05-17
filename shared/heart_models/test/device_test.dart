import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

void main() {
  group('DevicePlatform.fromString', () {
    for (final (raw, expected) in <(String, DevicePlatform)>[
      ('ios', .ios),
      ('iOS', .ios),
      ('android', .android),
      ('Android', .android),
      ('web', .web),
    ]) {
      test('parses $raw', () {
        expect(DevicePlatform.fromString(raw), expected);
      });
    }

    for (final raw in ['windows', '', 'macos', 'linux']) {
      test('throws on $raw', () {
        expect(() => DevicePlatform.fromString(raw), throwsA(isA<ArgumentError>()));
      });
    }
  });

  group('DevicePlatform value matches the wire form', () {
    for (final (p, wire) in <(DevicePlatform, String)>[
      (.ios, 'ios'),
      (.android, 'android'),
      (.web, 'web'),
    ]) {
      test('${p.name} -> $wire', () {
        expect(p.value, wire);
      });
    }
  });
}
