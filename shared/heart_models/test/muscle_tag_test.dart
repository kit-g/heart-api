import 'dart:convert';
import 'dart:io';

import 'package:body_atlas/body_atlas.dart' show MuscleGroup;
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
  group('muscle groups', () {
    test('a muscle id belongs to its group, either side', () {
      expect(MuscleGroupKey.ofMuscle('pectoralis_major_l'), MuscleGroupKey.chest);
      expect(MuscleGroupKey.ofMuscle('latissimus_dorsi_r'), MuscleGroupKey.back);
      expect(MuscleGroupKey.ofMuscle('rectus_abdominis_2_l'), MuscleGroupKey.core);
      expect(MuscleGroupKey.ofMuscle('pectoralis_major'), MuscleGroupKey.chest, reason: 'no side');
      expect(MuscleGroupKey.ofMuscle('not_a_muscle_l'), isNull);
    });

    test('the keys are the body map\'s own groups', () {
      // goals store these keys: a group the atlas renames must fail here, not
      // quietly stop counting
      expect([for (final key in MuscleGroupKey.values) key.value], [for (final group in MuscleGroup.values) group.id]);
    });

    test('a group is reached by naming a muscle in it, not only by name', () {
      final bench = MuscleTagging.fromJson(const {
        'primary': {
          'ids': ['pectoralis_major_l', 'pectoralis_major_r'],
        },
        'secondary': {
          'ids': ['anterior_deltoid_l', 'triceps_brachii_caput_longum_l'],
        },
      });
      expect(bench.shareOf('chest'), 1.0);
      expect(bench.shareOf('arms'), 0.5);
      expect(bench.shareOf('legs'), 0.0);
      expect(bench.groupShares, {
        MuscleGroupKey.chest: 1.0,
        MuscleGroupKey.shoulders: 0.5,
        MuscleGroupKey.arms: 0.5,
      });
    });

    test('a group in both roles counts once, as primary, at the role shares', () {
      final pullUp = MuscleTagging.fromJson(const {
        'primary': {
          'ids': ['latissimus_dorsi_l'],
          'share': 0.75,
        },
        'secondary': {
          'groups': ['back', 'arms', 'unknown'],
          'share': 0.25,
        },
      });
      expect(pullUp.groupShares, {MuscleGroupKey.back: 0.75, MuscleGroupKey.arms: 0.25});
      expect(pullUp.primaryGroups, {MuscleGroupKey.back});
      expect(MuscleTagging.empty().groupShares, isEmpty);
      expect(MuscleTagging.empty().primaryGroups, isEmpty);
    });

    test('every muscle id the library may tag belongs to a group', () {
      // the content schema is the library's muscle vocabulary: a muscle added
      // there and not here would count toward no group
      final schema = jsonDecode(File('../../content/exercise_library_schema.json').readAsStringSync());
      final ids = switch (schema) {
        {r'$defs': {'muscleList': {'items': {'enum': final List ids}}}} => ids,
        _ => const [],
      };
      expect(ids, isNotEmpty);
      expect([
        for (final id in ids.cast<String>())
          if (MuscleGroupKey.ofMuscle(id) == null) id,
      ], isEmpty);
    });

    test('a target names the group an untagged exercise falls to', () {
      expect(Target.shoulder.muscleGroup, MuscleGroupKey.shoulders);
      expect(Target.cardio.muscleGroup, isNull);
    });
  });
}
