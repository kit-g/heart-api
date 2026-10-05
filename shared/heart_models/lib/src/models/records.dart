import 'exercise.dart';

/// Folds one exercise's sets — every completed, non-warm-up set, oldest
/// workout first — into its personal records. Null when the exercise has
/// never been performed.
///
/// The one definition of a personal record, shared by everything that shows
/// one, so a record reads the same wherever it is computed.
///
/// Every record is the *set* it happened on, never two independent maxima
/// glued together (the old query reported max(weight) alongside max(reps),
/// describing a set that may never have existed). Shape, by [category]:
///
/// - barbell / dumbbell / machine / weightedBodyWeight:
///   `heaviest {weight, reps?, workoutId, at}`,
///   `oneRepMax {value, weight, reps, workoutId, at}` (Brzycki),
///   `bestVolume {value, weight, reps, workoutId, at}` (weight × reps),
///   `repMaxes [{reps 1..10, weight, workoutId, at}]`, `totalVolume`
/// - assistedBodyWeight: `mostReps`, `lightestAssistance` (weight is the
///   assistance, so less is better)
/// - repsOnly: `mostReps {reps, workoutId, at}`, `totalReps`
/// - duration: `longestDuration {duration, workoutId, at}`, `totalDuration`
/// - cardio: `longestDistance`, `longestDuration`,
///   `bestPace {pace (s per km), distance, duration, workoutId, at}`,
///   `totalDistance`
///
/// Always: `sessions` (distinct workouts) and `firstAt` (ISO). Ties keep the
/// earlier set — a record credits the first time it was hit.
///
/// Each headline record also carries `previous`: the same record over the
/// sessions before its own — what it beat ("was 95 kg"). Later sessions never
/// count: a record can't have beaten a set that came after it. Absent when no
/// earlier session has a value to beat, which is how a first-ever record
/// reads. `repMaxes` entries do not carry one.
Map<String, Object>? foldRecords(Category category, List<RecordSet> sets) {
  if (sets.isEmpty) return null;

  final records = _fold(category, sets);
  if (records == null) return null;

  // one re-fold per session holding a record, not per record: a good
  // session usually holds several
  final without = <String, Map<String, Object>?>{};
  for (final MapEntry(:key, :value) in records.entries.toList()) {
    if (value case {'workoutId': final String holder}) {
      final others = without.putIfAbsent(
        holder,
        // sets arrive oldest first, a session's sets together: everything
        // before the holder's first set is everything it could have beaten
        () => _fold(category, sets.takeWhile((set) => set.workoutId != holder).toList()),
      );
      if (others?[key] case final Map previous) records[key] = {...value, 'previous': previous};
    }
  }

  return records;
}

/// [_foldRecords] without the `previous` pass.
Map<String, Object>? _fold(Category category, List<RecordSet> sets) {
  if (sets.isEmpty) return null;

  final records = <String, Object>{
    'sessions': sets.map((set) => set.workoutId).toSet().length,
    'firstAt': sets.first.at,
  };

  switch (category) {
    case .barbell || .dumbbell || .machine || .weightedBodyWeight:
      RecordSet? heaviest;
      RecordSet? oneRepMax;
      RecordSet? bestVolume;
      final repMaxes = <int, RecordSet>{};
      var totalVolume = 0.0;

      for (final set in sets) {
        final RecordSet(:weight, :reps) = set;
        if (weight == null) continue;
        if (weight > (heaviest?.weight ?? -1)) heaviest = set;
        if (reps == null || reps <= 0) continue;

        totalVolume += weight * reps;
        if (weight * reps > (bestVolume?.volume ?? -1)) bestVolume = set;
        // the Brzycki denominator crosses zero just under 37 reps; past that
        // the estimate is meaningless, not merely imprecise
        if (reps < 37 && set.oneRepMax > (oneRepMax?.oneRepMax ?? -1)) oneRepMax = set;
        if (reps <= 10 && weight > (repMaxes[reps]?.weight ?? -1)) repMaxes[reps] = set;
      }

      if (heaviest case final set?) {
        records['heaviest'] = {'weight': set.weight, 'reps': ?set.reps, 'workoutId': set.workoutId, 'at': set.at};
      }
      if (oneRepMax case final set?) {
        records['oneRepMax'] = {
          'value': set.oneRepMax,
          'weight': set.weight,
          'reps': set.reps,
          'workoutId': set.workoutId,
          'at': set.at,
        };
      }
      if (bestVolume case final set?) {
        records['bestVolume'] = {
          'value': set.volume,
          'weight': set.weight,
          'reps': set.reps,
          'workoutId': set.workoutId,
          'at': set.at,
        };
      }
      if (repMaxes.isNotEmpty) {
        records['repMaxes'] = [
          for (final reps in (repMaxes.keys.toList()..sort()))
            {
              'reps': reps,
              'weight': repMaxes[reps]!.weight,
              'workoutId': repMaxes[reps]!.workoutId,
              'at': repMaxes[reps]!.at,
            },
        ];
      }
      // any set with weight and reps has volume, rep max or not (a block of
      // twelves sets none, since rep maxes stop at ten)
      if (bestVolume != null) records['totalVolume'] = totalVolume;

    case .assistedBodyWeight:
      RecordSet? mostReps;
      RecordSet? lightest;

      for (final set in sets) {
        final RecordSet(:weight, :reps) = set;
        if (reps != null && reps > (mostReps?.reps ?? -1)) mostReps = set;
        if (weight != null && weight < (lightest?.weight ?? double.infinity)) lightest = set;
      }

      if (mostReps case final set?) {
        records['mostReps'] = {'reps': set.reps, 'weight': ?set.weight, 'workoutId': set.workoutId, 'at': set.at};
      }
      if (lightest case final set?) {
        records['lightestAssistance'] = {
          'weight': set.weight,
          'reps': ?set.reps,
          'workoutId': set.workoutId,
          'at': set.at,
        };
      }

    case .repsOnly:
      RecordSet? mostReps;
      var totalReps = 0;

      for (final set in sets) {
        final reps = set.reps;
        if (reps == null) continue;
        totalReps += reps;
        if (reps > (mostReps?.reps ?? -1)) mostReps = set;
      }

      if (mostReps case final set?) {
        records['mostReps'] = {'reps': set.reps, 'workoutId': set.workoutId, 'at': set.at};
        records['totalReps'] = totalReps;
      }

    case .duration:
      RecordSet? longest;
      var totalDuration = 0.0;

      for (final set in sets) {
        final duration = set.duration;
        if (duration == null) continue;
        totalDuration += duration;
        if (duration > (longest?.duration ?? -1)) longest = set;
      }

      if (longest case final set?) {
        records['longestDuration'] = {'duration': set.duration, 'workoutId': set.workoutId, 'at': set.at};
        records['totalDuration'] = totalDuration;
      }

    case .cardio:
      RecordSet? longestDistance;
      RecordSet? longestDuration;
      RecordSet? bestPace;
      var totalDistance = 0.0;

      for (final set in sets) {
        final RecordSet(:distance, :duration) = set;
        if (distance != null) {
          totalDistance += distance;
          if (distance > (longestDistance?.distance ?? -1)) longestDistance = set;
        }
        if (duration != null && duration > (longestDuration?.duration ?? -1)) longestDuration = set;
        if (set.pace case final pace? when pace < (bestPace?.pace ?? double.infinity)) bestPace = set;
      }

      if (longestDistance case final set?) {
        records['longestDistance'] = {
          'distance': set.distance,
          'duration': ?set.duration,
          'workoutId': set.workoutId,
          'at': set.at,
        };
        records['totalDistance'] = totalDistance;
      }
      if (longestDuration case final set?) {
        records['longestDuration'] = {
          'duration': set.duration,
          'distance': ?set.distance,
          'workoutId': set.workoutId,
          'at': set.at,
        };
      }
      if (bestPace case final set?) {
        records['bestPace'] = {
          'pace': set.pace,
          'distance': set.distance,
          'duration': set.duration,
          'workoutId': set.workoutId,
          'at': set.at,
        };
      }

    // A carry or a loaded hold has two records a lifter brags about: the
    // heaviest load, and the farthest or longest they went with any load.
    // Weight × distance is what `best` ranks by in the model, but "40 kg·km"
    // is not a number anyone recognises, so it stays off the records.
    case .weightedDistance:
      RecordSet? heaviest;
      RecordSet? farthest;
      var totalDistance = 0.0;

      for (final set in sets) {
        final RecordSet(:weight, :distance) = set;
        if (weight != null && weight > (heaviest?.weight ?? -1)) heaviest = set;
        if (distance == null) continue;
        totalDistance += distance;
        if (distance > (farthest?.distance ?? -1)) farthest = set;
      }

      if (heaviest case final set?) {
        records['heaviest'] = {
          'weight': set.weight,
          'distance': ?set.distance,
          'workoutId': set.workoutId,
          'at': set.at,
        };
      }
      if (farthest case final set?) {
        records['longestDistance'] = {
          'distance': set.distance,
          'weight': ?set.weight,
          'workoutId': set.workoutId,
          'at': set.at,
        };
        records['totalDistance'] = totalDistance;
      }

    case .weightedDuration:
      RecordSet? heaviest;
      RecordSet? longest;
      var totalDuration = 0.0;

      for (final set in sets) {
        final RecordSet(:weight, :duration) = set;
        if (weight != null && weight > (heaviest?.weight ?? -1)) heaviest = set;
        if (duration == null) continue;
        totalDuration += duration;
        if (duration > (longest?.duration ?? -1)) longest = set;
      }

      if (heaviest case final set?) {
        records['heaviest'] = {
          'weight': set.weight,
          'duration': ?set.duration,
          'workoutId': set.workoutId,
          'at': set.at,
        };
      }
      if (longest case final set?) {
        records['longestDuration'] = {
          'duration': set.duration,
          'weight': ?set.weight,
          'workoutId': set.workoutId,
          'at': set.at,
        };
        records['totalDuration'] = totalDuration;
      }
  }

  // sessions and firstAt alone mean every measured value was null — the
  // caller treats that the same as never performed
  return records.length > 2 ? records : null;
}

/// One completed set with its workout's identity and start ([at], ISO 8601):
/// the input [foldRecords] works from.
class RecordSet {
  final double? weight;
  final int? reps;
  final double? duration;
  final double? distance;
  final String workoutId;
  final String at;

  const new({
    required this.weight,
    required this.reps,
    required this.duration,
    required this.distance,
    required this.workoutId,
    required this.at,
  });

  /// From a row with `weight`, `reps`, `duration`, `distance`, `workout_id`
  /// and `start` (ISO 8601).
  factory fromRow(Map<String, dynamic> row) {
    return RecordSet(
      weight: (row['weight'] as num?)?.toDouble(),
      reps: (row['reps'] as num?)?.toInt(),
      duration: (row['duration'] as num?)?.toDouble(),
      distance: (row['distance'] as num?)?.toDouble(),
      workoutId: row['workout_id'] as String,
      at: row['start'] as String,
    );
  }

  double get volume => (weight ?? 0) * (reps ?? 0);

  /// Brzycki. Callers guard the rep range.
  double get oneRepMax => (weight ?? 0) / (1.0278 - .0278 * (reps ?? 0));

  /// Seconds per unit of distance; null when either side is missing or zero.
  double? get pace {
    return switch ((duration, distance)) {
      (final double d, final double km) when d > 0 && km > 0 => d / km,
      _ => null,
    };
  }
}
