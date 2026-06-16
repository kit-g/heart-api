import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

void main() {
  group('Settings', () {
    test('empty when json is null', () {
      final s = Settings.fromJson(null);
      expect(s.unitSystem, isNull);
      expect(s.themeMode, isNull);
      expect(s.accentColor, isNull);
      expect(s.extra, isEmpty);
      expect(s.toMap(), <String, dynamic>{});
    });

    test('parses known fields and round-trips via toMap', () {
      final s = Settings.fromJson({
        'unitSystem': 'imperial',
        'themeMode': 'dark',
        'accentColor': '#ff0000',
      });
      expect(s.unitSystem, MeasurementUnit.imperial);
      expect(s.themeMode, 'dark');
      expect(s.accentColor, '#ff0000');
      expect(s.toMap(), {
        'unitSystem': 'imperial',
        'themeMode': 'dark',
        'accentColor': '#ff0000',
      });
    });

    test('preserves unknown keys in extra and re-emits them', () {
      final s = Settings.fromJson({
        'unitSystem': 'metric',
        'hapticsEnabled': true,
        'restTimerSeconds': 90,
      });
      expect(s.extra, {'hapticsEnabled': true, 'restTimerSeconds': 90});
      expect(s.toMap(), {
        'hapticsEnabled': true,
        'restTimerSeconds': 90,
        'unitSystem': 'metric',
      });
    });

    test('degrades an invalid unitSystem to null rather than throwing', () {
      final s = Settings.fromJson({'unitSystem': 'furlongs'});
      expect(s.unitSystem, isNull);
      // the bad value is not kept as an extra key either
      expect(s.toMap(), <String, dynamic>{});
    });
  });
}
