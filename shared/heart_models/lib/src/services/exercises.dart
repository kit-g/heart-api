import 'dart:math' as math;

import '../models/act.dart';
import '../models/charts.dart';
import '../models/exercise.dart';

abstract interface class ExerciseHistoryService {
  Future<List<(num, DateTime)>> getRepsHistory(String userId, Exercise exercise, {int? limit});

  Future<List<(num, DateTime)>> getWeightHistory(String userId, Exercise exercise, {int? limit});

  Future<List<(num, DateTime)>> getDistanceHistory(String userId, Exercise exercise, {int? limit});

  Future<List<(num, DateTime)>> getDurationHistory(String userId, Exercise exercise, {int? limit});
}

abstract interface class ExercisesMetricsService {
  Future<List<(num, DateTime)>?> getExerciseMetics(
    String userId,
    ChartPreferenceType type,
    String exerciseName, {
    int limit,
  });
}

abstract interface class ExerciseService implements ExerciseHistoryService, ExercisesMetricsService {
  Future<(DateTime?, Iterable<Exercise>)> getExercises({String? userId});

  Future<void> storeExercises(Iterable<Exercise> exercises, {String? userId});

  Future<Iterable<ExerciseAct>> getExerciseHistory(String userId, Exercise exercise, {int? pageSize, String? anchor});

  Future<Map?> getRecord(String userId, Exercise exercise);
}

abstract interface class RemoteExerciseService {
  Future<Iterable<Exercise>> getExercises();

  Future<Iterable<Exercise>> getOwnExercises();

  Future<Exercise> makeExercise(Exercise exercise);

  Future<Exercise> editExercise(Exercise exercise);
}

class FakeExerciseHistoryService implements ExerciseHistoryService {
  final _random = math.Random();

  Future<List<(num, DateTime)>> _generateFakeTimeline({
    required int weeksBack,
    required double startValue,
    required double volatility,
    required double growthBias,
  }) async {
    final now = DateTime.timestamp();

    final timeline = Iterable.generate(weeksBack + 1).toList().reversed.fold<List<(num, DateTime)>>(
      [],
      (acc, i) {
        final lastValue = acc.isEmpty ? startValue : acc.last.$1.toDouble();

        // random walk: bias it slightly upwards
        final change = (_random.nextDouble() - 0.4 + growthBias) * volatility;
        final newValue = math.max(startValue * 0.7, lastValue + change);

        // a slight jitter for the day to look natural
        final date = now.subtract(Duration(days: i * 7 + _random.nextInt(3)));

        return [...acc, (newValue.roundToDouble(), date)];
      },
    );

    // reversed so the most recent date is at the beginning of the list
    return timeline.reversed.toList();
  }

  @override
  Future<List<(num, DateTime)>> getRepsHistory(String userId, Exercise exercise, {int? limit}) {
    return _generateFakeTimeline(
      weeksBack: limit ?? 8,
      startValue: 8.0,
      volatility: 3.0,
      growthBias: 0.2,
    );
  }

  @override
  Future<List<(num, DateTime)>> getWeightHistory(String userId, Exercise exercise, {int? limit}) {
    return _generateFakeTimeline(
      weeksBack: limit ?? 8,
      startValue: 60.0,
      volatility: 15.0,
      growthBias: 0.25,
    );
  }

  @override
  Future<List<(num, DateTime)>> getDistanceHistory(String userId, Exercise exercise, {int? limit}) {
    return _generateFakeTimeline(
      weeksBack: limit ?? 8,
      startValue: 2.0,
      volatility: 0.8,
      growthBias: 0.15,
    );
  }

  @override
  Future<List<(num, DateTime)>> getDurationHistory(String userId, Exercise exercise, {int? limit}) {
    return _generateFakeTimeline(
      weeksBack: limit ?? 8,
      startValue: 300.0, // seconds
      volatility: 60.0,
      growthBias: 0.1,
    );
  }
}
