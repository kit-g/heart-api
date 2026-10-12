import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

void main() {
  final bench = Exercise.fromJson(const {
    'id': '0198c1a2-b3c4-7d5e-8f60-718293a4b5c6',
    'name': 'Bench Press',
    'category': 'Barbell',
    'target': 'Chest',
  });

  group('TargetRange', () {
    test('an exact number, a range and an open top', () {
      expect(TargetRange.exactly(8).isExact, isTrue);
      expect(const TargetRange(min: 6, max: 10).isExact, isFalse);
      expect(const TargetRange(min: 8).isOpen, isTrue);
    });

    test('round-trips, leaving an open top out', () {
      expect(TargetRange.fromJson(const {'min': 6, 'max': 10}).toMap(), {'min': 6, 'max': 10});
      expect(TargetRange.fromJson(const {'min': 8}).toMap(), {'min': 8});
      expect(TargetRange.fromJson(const {'min': 8, 'max': null}), const TargetRange(min: 8));
    });

    test('a shape this build predates is an ArgumentError', () {
      expect(() => TargetRange.fromJson(const {'share': 0.8}), throwsArgumentError);
      expect(() => TargetRange.fromJson(const {'min': 5, 'step': 1}), throwsArgumentError);
      expect(() => TargetRange.fromJson(const {'min': '5'}), throwsArgumentError);
    });
  });

  group('SetTarget', () {
    test('reads each measure it knows', () {
      final target = SetTarget.fromJson(const {
        'reps': {'min': 6, 'max': 10},
        'duration': {'min': 30, 'max': 30},
      });
      expect(target[.reps], const TargetRange(min: 6, max: 10));
      expect(target[.duration], TargetRange.exactly(30));
      expect(target[.weight], isNull);
      expect(target.isEmpty, isFalse);
    });

    test('carries a measure or a range shape it cannot read, and writes it back', () {
      const json = {
        'reps': {'min': 5},
        'weight': {'share': 0.8},
        'tempo': '3-1-1',
      };
      final target = SetTarget.fromJson(json);
      expect(target.ranges.keys, [TargetMeasure.reps]);
      expect(target.isEmpty, isFalse);
      expect(target.toMap(), json);
    });

    test('nothing readable is still not empty', () {
      expect(SetTarget.fromJson(const {'tempo': '3-1-1'}).isEmpty, isFalse);
      expect(SetTarget.fromJson(const {}).isEmpty, isTrue);
      expect(SetTarget.none.isEmpty, isTrue);
    });

    test('withRange replaces one measure and keeps the rest, unread included', () {
      final target = SetTarget.fromJson(const {
        'reps': {'min': 5},
        'weight': {'share': 0.8},
        'tempo': '3-1-1',
      });

      expect(target.withRange(.reps, const TargetRange(min: 6, max: 8)).toMap(), {
        'reps': {'min': 6, 'max': 8},
        'weight': {'share': 0.8},
        'tempo': '3-1-1',
      });
      expect(target.withRange(.reps, null).toMap(), {
        'weight': {'share': 0.8},
        'tempo': '3-1-1',
      });
      // the user set the weight, so the share this build could not read goes
      expect(target.withRange(.weight, TargetRange.exactly(60)).toMap(), {
        'reps': {'min': 5},
        'weight': {'min': 60, 'max': 60},
        'tempo': '3-1-1',
      });
    });
  });

  group('ExerciseSet.target', () {
    test('a set that never spoke about a target writes no key', () {
      final logged = ExerciseSet.fromJson(bench, const {'id': 's1', 'reps': 5, 'weight': 100});
      expect(logged.target, isNull);
      expect(logged.toMap().containsKey('target'), isFalse);
    });

    test('a template set reads its target and always writes the key', () {
      final set = ExerciseSet.fromJson(bench, const {
        'id': 's1',
        'reps': 8,
        'target': {
          'reps': {'min': 6, 'max': 10},
        },
      });
      expect(set.target?[.reps], const TargetRange(min: 6, max: 10));
      expect(set.toMap()['target'], {
        'reps': {'min': 6, 'max': 10},
      });

      final none = ExerciseSet.fromJson(bench, const {'id': 's2', 'reps': 8, 'target': null});
      expect(none.target, isNull);
      expect(none.toMap(), containsPair('target', null));
    });

    test('clearing writes null, so the stored target goes', () {
      final set = ExerciseSet(bench, reps: 8, target: SetTarget({.reps: TargetRange.exactly(8)}));
      expect(set.toMap()['target'], {
        'reps': {'min': 8, 'max': 8},
      });

      set.target = SetTarget.none;
      expect(set.target, isNull);
      expect(set.toMap(), containsPair('target', null));
    });

    test('a copy keeps the target, for a session started from a template', () {
      final set = ExerciseSet(bench, reps: 8, target: SetTarget({.reps: const TargetRange(min: 8)}));
      expect(set.copy().target?[.reps], const TargetRange(min: 8));
      expect(set.copy(sameId: true).toMap()['target'], {
        'reps': {'min': 8},
      });
    });

    test('a target this build cannot read survives a read and a write', () {
      const target = {
        'weight': {'share': 0.8},
      };
      final set = ExerciseSet.fromJson(bench, const {'id': 's1', 'reps': 5, 'target': target});
      expect(set.toMap()['target'], target);
    });
  });

  group('TemplateSetRequest.target', () {
    Map<String, dynamic> encode(TemplateSetRequest set) => set.toJson();

    test('absent says nothing, none clears, a target is written', () {
      expect(encode(const TemplateSetRequest(reps: 5)).containsKey('target'), isFalse);
      expect(encode(TemplateSetRequest(reps: 5, target: SetTarget.none)), containsPair('target', null));
      expect(encode(TemplateSetRequest(reps: 5, target: SetTarget({.reps: const TargetRange(min: 5)}))), {
        'reps': 5,
        'target': {
          'reps': {'min': 5},
        },
      });
    });
  });
}
