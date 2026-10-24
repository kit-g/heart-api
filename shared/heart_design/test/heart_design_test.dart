import 'dart:io';
import 'dart:math';

import 'package:heart_design/heart_design.dart';
import 'package:test/test.dart';

import '../tool/generator.dart';

void main() {
  test('the generated files are what tokens.json makes (run `make design`)', () {
    for (final MapEntry(key: path, value: contents) in outputs(File('tokens.json').readAsStringSync()).entries) {
      expect(File(path).readAsStringSync(), contents, reason: path);
    }
  });

  group('every palette', () {
    final palettes = {
      for (final preset in Preset.values) ...{'${preset.name} light': preset.light, '${preset.name} dark': preset.dark},
    };

    test('keeps muted text at WCAG AA on the ground', () {
      for (final MapEntry(key: name, value: palette) in palettes.entries) {
        expect(_contrast(palette.muted, palette.ground), greaterThanOrEqualTo(4.5), reason: name);
      }
    });

    test('keeps ink and accentInk legible on the ground', () {
      for (final MapEntry(key: name, value: palette) in palettes.entries) {
        expect(_contrast(palette.ink, palette.ground), greaterThanOrEqualTo(7), reason: name);
        expect(_contrast(palette.accentInk, palette.ground), greaterThanOrEqualTo(4.5), reason: name);
      }
    });
  });

  test('a malformed token is refused, naming where', () {
    final broken = File('tokens.json').readAsStringSync().replaceFirst('"#FFFFFF"', '"#fff"');
    expect(
      () => outputs(broken),
      throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('forge.light.ground'))),
    );
  });
}

/// The WCAG contrast ratio of two opaque ARGB colors.
double _contrast(int a, int b) {
  final (la, lb) = (_luminance(a), _luminance(b));
  return (max(la, lb) + 0.05) / (min(la, lb) + 0.05);
}

double _luminance(int argb) {
  double channel(int shift) {
    final c = ((argb >> shift) & 0xFF) / 255;
    return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0);
}
