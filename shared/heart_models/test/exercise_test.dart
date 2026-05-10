import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

void main() {
  group('Category', () {
    test('value and toString return label', () {
      for (final c in Category.values) {
        expect(c.value, isNotEmpty);
        expect(c.toString(), c.value);
      }
    });

    test('fromString parses all valid values', () {
      for (final c in Category.values) {
        expect(Category.fromString(c.value), c, reason: 'Failed for ${c.value}');
      }
    });

    test('fromString throws on invalid', () {
      expect(() => Category.fromString('Nope'), throwsArgumentError);
    });

    test('canSwitchTo only true within weight categories', () {
      final weight = {
        Category.weightedBodyWeight,
        Category.machine,
        Category.dumbbell,
        Category.barbell,
      };
      final nonWeight = {
        Category.assistedBodyWeight,
        Category.repsOnly,
        Category.cardio,
        Category.duration,
      };

      // weight <-> weight: true
      for (final a in weight) {
        for (final b in weight) {
          expect(a.canSwitchTo(b), isTrue, reason: '$a -> $b should be switchable');
        }
      }

      // weight -> nonWeight: false
      for (final a in weight) {
        for (final b in nonWeight) {
          expect(a.canSwitchTo(b), isFalse, reason: '$a -> $b should NOT be switchable');
        }
      }

      // nonWeight -> weight: false
      for (final a in nonWeight) {
        for (final b in weight) {
          expect(a.canSwitchTo(b), isFalse, reason: '$a -> $b should NOT be switchable');
        }
      }

      // nonWeight <-> nonWeight: false
      for (final a in nonWeight) {
        for (final b in nonWeight) {
          expect(a.canSwitchTo(b), isFalse, reason: '$a -> $b should NOT be switchable');
        }
      }
    });
  });

  group('Target', () {
    test('value and toString return label', () {
      for (final t in Target.values) {
        expect(t.value, isNotEmpty);
        expect(t.toString(), t.value);
      }
    });

    test('fromString parses all valid values', () {
      for (final t in Target.values) {
        expect(Target.fromString(t.value), t, reason: 'Failed for ${t.value}');
      }
    });

    test('fromString throws on invalid', () {
      expect(() => Target.fromString('Nope'), throwsArgumentError);
    });

    test('icon is defined for all values', () {
      for (final t in Target.values) {
        expect(t.icon, isNotEmpty, reason: 'Missing icon for $t');
      }
    });
  });

  group('_Exercise model', () {
    const baseJson = {
      'category': 'Weighted Body Weight',
      'name': 'Bench Press',
      'target': 'Chest',
    };

    test('factory Exercise() asserts non-empty name', () {
      expect(
        () => Exercise(name: '', category: Category.machine, target: Target.arms),
        throwsA(isA<AssertionError>()),
      );
    });

    test('fromJson minimal creates model, toMap round-trips base fields', () {
      final e = Exercise.fromJson(baseJson);
      expect(e.name, 'Bench Press');
      expect(e.category, Category.weightedBodyWeight);
      expect(e.target, Target.chest);
      expect(e.asset, isNull);
      expect(e.thumbnail, isNull);
      expect(e.instructions, isNull);
      expect(e.isMine, isFalse);
      expect(e.isArchived, isFalse);
      expect(e.muscles.isEmpty, isTrue);

      expect(e.toMap(), {...baseJson, 'own': 0, 'archived': 0});
    });

    test('fromJson with muscles, toMap includes it', () {
      final json = {
        ...baseJson,
        'muscles': {
          'primary': {
            'ids': ['chest_middle'],
            'groups': ['chest']
          },
        },
      };
      final e = Exercise.fromJson(json);
      expect(e.muscles.isEmpty, isFalse);
      expect(e.muscles.primary.ids, contains('chest_middle'));

      final map = e.toMap();
      expect(map['muscles'], contains('primary'));
    });

    test('factory Exercise() defaults muscles to empty', () {
      final e = Exercise(
        name: 'Test',
        category: Category.barbell,
        target: Target.chest,
      );
      expect(e.muscles.isEmpty, isTrue);
    });

    test('fromJson accepts remote-shaped asset/thumbnail', () {
      final json = {
        ...baseJson,
        'asset': {'link': 'https://a', 'width': 100, 'height': 200},
        'thumbnail': {'link': 'https://t', 'width': 20, 'height': 40},
        'instructions': 'Keep elbows in',
        'own': true,
        'archived': true,
      };
      final e = Exercise.fromJson(json);
      expect(e.asset, isNotNull);
      expect(e.asset!.link, 'https://a');
      expect(e.asset!.width, 100);
      expect(e.asset!.height, 200);
      expect(e.thumbnail, isNotNull);
      expect(e.thumbnail!.link, 'https://t');
      expect(e.thumbnail!.width, 20);
      expect(e.thumbnail!.height, 40);
      expect(e.instructions, 'Keep elbows in');
      expect(e.isMine, isTrue);
      expect(e.isArchived, isTrue);

      // toMap should flatten to primitive link fields
      final map = e.toMap();
      expect(map['asset'], 'https://a');
      expect(map['assetWidth'], 100);
      expect(map['assetHeight'], 200);
      expect(map['thumbnail'], 'https://t');
      expect(map['thumbnailWidth'], 20);
      expect(map['thumbnailHeight'], 40);
      expect(map['instructions'], 'Keep elbows in');
    });

    test('fromJson accepts local-shaped asset/thumbnail', () {
      final json = {
        ...baseJson,
        'asset': 'file://a',
        'assetWidth': 640,
        'assetHeight': 480,
        'thumbnail': 'file://t',
        'thumbnailWidth': 64,
        'thumbnailHeight': 64,
      };
      final e = Exercise.fromJson(json);
      expect(e.asset, isNotNull);
      expect(e.asset!.link, 'file://a');
      expect(e.asset!.width, 640);
      expect(e.asset!.height, 480);
      expect(e.thumbnail, isNotNull);
      expect(e.thumbnail!.link, 'file://t');
      expect(e.thumbnail!.width, 64);
      expect(e.thumbnail!.height, 64);

      final map = e.toMap();
      expect(map['asset'], 'file://a');
      expect(map['assetWidth'], 640);
      expect(map['assetHeight'], 480);
      expect(map['thumbnail'], 'file://t');
      expect(map['thumbnailWidth'], 64);
      expect(map['thumbnailHeight'], 64);
    });

    group('contains()', () {
      final e = Exercise(
        name: 'Bench Press (Barbell)',
        category: Category.barbell,
        target: Target.chest,
      );

      final eWithDash = Exercise(
        name: 'Iso-Lateral Chest Press (Machine)',
        category: Category.barbell,
        target: Target.chest,
      );

      test('empty query returns true', () {
        expect(e.contains(''), isTrue);
      });

      test('matches case-insensitively by tokens', () {
        expect(e.contains('bench'), isTrue);
        expect(e.contains('Bench'), isTrue);
        expect(e.contains('Press'), isTrue);
        expect(e.contains('barb'), isTrue);
        expect(e.contains('barbell'), isTrue);
      });

      test('matches multiple words, order-insensitive, substring per word', () {
        expect(e.contains('bench press'), isTrue);
        expect(e.contains('press bench'), isTrue);
        expect(e.contains('ben pre'), isTrue);
      });

      test('trims and handles extra spaces/parentheses', () {
        expect(e.contains(' Press'), isTrue);
        expect(e.contains(' press '), isTrue);
        expect(e.contains('bench   press'), isTrue);
      });

      test('non-matching returns false', () {
        expect(e.contains('squat'), isFalse);
        expect(e.contains('dumbbell only'), isFalse);
      });

      test('non-matching returns false', () {
        expect(eWithDash.contains('isolateral'), isTrue);
        expect(eWithDash.contains('press'), isTrue);
      });
    });

    group('fits()', () {
      final chestWeighted = Exercise(
        name: 'Bench',
        category: Category.barbell,
        target: Target.chest,
      );
      final legsWeighted = Exercise(
        name: 'Squat',
        category: Category.barbell,
        target: Target.legs,
      );
      final cardio = Exercise(
        name: 'Run',
        category: Category.cardio,
        target: Target.cardio,
      );

      test('no filters => always true', () {
        expect(chestWeighted.fits([]), isTrue);
        expect(legsWeighted.fits([]), isTrue);
        expect(cardio.fits([]), isTrue);
      });

      test('category-only filters', () {
        expect(chestWeighted.fits([Category.barbell]), isTrue);
        expect(chestWeighted.fits([Category.cardio]), isFalse);
      });

      test('target-only filters', () {
        expect(chestWeighted.fits([Target.chest]), isTrue);
        expect(chestWeighted.fits([Target.legs]), isFalse);
      });

      test('both category and target must match', () {
        // match both
        expect(chestWeighted.fits([Category.barbell, Target.chest]), isTrue);
        // category mismatch
        expect(chestWeighted.fits([Category.cardio, Target.chest]), isFalse);
        // target mismatch
        expect(chestWeighted.fits([Category.barbell, Target.legs]), isFalse);
      });

      test('multiple filters: contains in any of each type', () {
        // category among many, target among many
        expect(
          chestWeighted.fits([Category.machine, Category.barbell, Target.back, Target.chest]),
          isTrue,
        );
        // category ok, target missing among provided
        expect(
          chestWeighted.fits([Category.barbell, Target.back, Target.legs]),
          isFalse,
        );
        // target ok, category missing among provided
        expect(
          chestWeighted.fits([Category.machine, Target.chest]),
          isFalse,
        );
      });
    });

    group('equality/hash/compare', () {
      test('equality and hashCode depend on name only', () {
        final a1 = Exercise(name: 'Bench', category: Category.barbell, target: Target.chest);
        final a2 = Exercise(name: 'Bench', category: Category.machine, target: Target.back);
        final b = Exercise(name: 'Squat', category: Category.barbell, target: Target.legs);

        expect(a1, equals(a2));
        expect(a1.hashCode, equals(a2.hashCode));
        expect(a1 == b, isFalse);
      });

      test('compareTo uses case-insensitive name ordering', () {
        final a = Exercise(name: 'alpha', category: Category.barbell, target: Target.chest);
        final b = Exercise(name: 'Bravo', category: Category.barbell, target: Target.chest);
        final c = Exercise(name: 'charlie', category: Category.barbell, target: Target.chest);

        final list = [c, b, a]..sort();
        expect(list.map((e) => e.name).toList(), ['alpha', 'Bravo', 'charlie']);
      });
    });

    group('hasInfo and copyWith', () {
      test('hasInfo true when any of asset/instructions/thumbnail present', () {
        final base = Exercise(name: 'X', category: Category.cardio, target: Target.cardio);
        expect(base.hasInfo, isFalse);

        final withAsset = base.copyWith(asset: (link: 'l', width: 1, height: 2));
        expect(withAsset.hasInfo, isTrue);

        final withThumb = base.copyWith(thumbnail: (link: 't', width: 3, height: 4));
        expect(withThumb.hasInfo, isTrue);

        final withInstr = base.copyWith(instructions: 'Do it');
        expect(withInstr.hasInfo, isTrue);
      });

      test('copyWith replaces only provided fields, preserves others', () {
        final base = Exercise(
          name: 'X',
          category: Category.barbell,
          target: Target.chest,
          instructions: 'A',
        );
        final tagging = MuscleTagging.fromJson({
          'primary': {'ids': ['p']}
        });
        final copied = base.copyWith(
          category: Category.machine,
          target: Target.back,
          isMine: true,
          isArchived: true,
          asset: (link: 'a', width: 10, height: 20),
          thumbnail: (link: 't', width: 1, height: 2),
          tags: tagging,
        );

        expect(copied.name, 'X');
        expect(copied.category, Category.machine);
        expect(copied.target, Target.back);
        expect(copied.isMine, isTrue);
        expect(copied.isArchived, isTrue);
        expect(copied.asset?.link, 'a');
        expect(copied.thumbnail?.link, 't');
        expect(copied.instructions, 'A', reason: 'not overridden');
        expect(copied.muscles, tagging);
      });
    });
  });
}
