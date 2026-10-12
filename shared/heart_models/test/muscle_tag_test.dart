import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

void main() {
  group('MuscleTag', () {
    test('fromJson handles valid data', () {
      final json = {
        'ids': ['abs', 'obliques'],
        'groups': ['core'],
      };
      final tag = MuscleTag.fromJson(json);
      expect(tag.ids, containsAll(['abs', 'obliques']));
      expect(tag.groups, containsAll(['core']));
      expect(tag.isEmpty, isFalse);
    });

    test('fromJson handles empty list', () {
      final json = {
        'ids': [],
        'groups': [],
      };
      final tag = MuscleTag.fromJson(json);
      expect(tag.ids, isEmpty);
      expect(tag.groups, isEmpty);
      expect(tag.isEmpty, isTrue);
    });

    test('fromJson handles missing fields', () {
      final json = <String, dynamic>{};
      final tag = MuscleTag.fromJson(json);
      expect(tag.ids, isEmpty);
      expect(tag.groups, isEmpty);
      expect(tag.isEmpty, isTrue);
    });

    test('empty() creates empty MuscleTag', () {
      final tag = MuscleTag.empty();
      expect(tag.ids, isEmpty);
      expect(tag.groups, isEmpty);
      expect(tag.isEmpty, isTrue);
    });

    test('toMap round-trips correctly', () {
      final tag = MuscleTag.fromJson({
        'ids': ['abs'],
        'groups': ['core'],
      });
      final map = tag.toMap();
      expect(map['ids'], ['abs']);
      expect(map['groups'], ['core']);
    });
  });

  group('MuscleTagging', () {
    test('fromJson handles valid primary and secondary', () {
      final json = {
        'primary': {
          'ids': ['chest_upper'],
          'groups': ['chest'],
        },
        'secondary': {
          'ids': ['triceps'],
          'groups': ['arms'],
        },
      };
      final tagging = MuscleTagging.fromJson(json);
      expect(tagging.primary.ids, contains('chest_upper'));
      expect(tagging.secondary?.ids, contains('triceps'));
      expect(tagging.isEmpty, isFalse);
    });

    test('fromJson handles missing secondary', () {
      final json = {
        'primary': {
          'ids': ['chest'],
          'groups': ['chest'],
        },
      };
      final tagging = MuscleTagging.fromJson(json);
      expect(tagging.primary.ids, contains('chest'));
      expect(tagging.secondary, isNull);
      expect(tagging.isEmpty, isFalse);
    });

    test('fromJson handles empty primary', () {
      final json = {
        'primary': {},
      };
      final tagging = MuscleTagging.fromJson(json);
      expect(tagging.primary.isEmpty, isTrue);
      expect(tagging.secondary, isNull);
      expect(tagging.isEmpty, isTrue);
    });

    test('empty() creates empty MuscleTagging', () {
      final tagging = MuscleTagging.empty();
      expect(tagging.primary.isEmpty, isTrue);
      expect(tagging.secondary, isNull);
      expect(tagging.isEmpty, isTrue);
    });

    test('toMap includes secondary only when present', () {
      final withSecondary = MuscleTagging.fromJson({
        'primary': {
          'ids': ['a'],
        },
        'secondary': {
          'ids': ['b'],
        },
      });
      expect(withSecondary.toMap(), contains('secondary'));

      final withoutSecondary = MuscleTagging.fromJson({
        'primary': {
          'ids': ['a'],
        },
      });
      expect(withoutSecondary.toMap(), isNot(contains('secondary')));
    });

    test('isEmpty is true only when primary and secondary are empty', () {
      expect(MuscleTagging.empty().isEmpty, isTrue);

      final onlyPrimary = MuscleTagging.fromJson({
        'primary': {
          'ids': ['a'],
        },
      });
      expect(onlyPrimary.isEmpty, isFalse);

      final withSecondary = MuscleTagging.fromJson({
        'primary': {},
        'secondary': {
          'ids': ['b'],
        },
      });
      expect(withSecondary.isEmpty, isFalse);
    });
  });
  group('muscle shares (heart-api#197)', () {
    final bench = MuscleTagging.fromJson(const {
      'primary': {
        'ids': ['pectoralis_major_l', 'pectoralis_major_r'],
        'groups': ['chest'],
      },
      'secondary': {
        'ids': ['anterior_deltoid_l', 'triceps_brachii_caput_longum_l'],
      },
    });

    test('a role without a share takes the default: all of a set, or half', () {
      expect(bench.primaryShare, 1.0);
      expect(bench.secondaryShare, 0.5);
      expect(bench.primary.toMap().containsKey('share'), isFalse);
    });

    test('shareOf matches an id prefix or a group, primary first', () {
      expect(bench.shareOf('pectoralis_major'), 1.0);
      expect(bench.shareOf('chest'), 1.0);
      expect(bench.shareOf('triceps_brachii'), 0.5);
      expect(bench.shareOf('biceps_brachii'), 0.0);
    });

    test('a role may say its own share, and it round-trips', () {
      final curl = MuscleTagging.fromJson(const {
        'primary': {
          'ids': ['biceps_brachii_l'],
        },
        'secondary': {
          'ids': ['brachioradialis_l'],
          'share': 0.25,
        },
      });
      expect(curl.secondaryShare, 0.25);
      expect(curl.shareOf('brachioradialis'), 0.25);
      expect(curl.toMap()['secondary'], containsPair('share', 0.25));
    });

    test('a muscle tagged in both roles counts as primary', () {
      final tagging = MuscleTagging.fromJson(const {
        'primary': {
          'groups': ['back'],
        },
        'secondary': {
          'groups': ['back'],
        },
      });
      expect(tagging.shareOf('back'), 1.0);
    });
  });
}
