# Changelog

## 1.3.0

- `WorkoutExercise` gains an optional `note` — a short, user-authored pin describing how the
  exercise is performed (e.g. "do one hand at a time"), distinct from a comment. Round-trips through
  `fromJson`/`toMap` and is carried forward by `Workout.copy()` (it's an instruction, not a
  measurement like `met`). Additive; null when unset. The server caps it at 500 characters.

## 1.2.0

- `GoalService.getTargetUserGoals` gains an optional `archived` flag: `false` (default) returns the
  live goals, `true` returns only the archived ones — the achieved surface behind a completed card.
  Additive; existing callers are unaffected.
- `GoalStage` gains an optional `achievedBy` (workout id crediting the session that met the rung),
  round-tripped through `fromJson`/`toMap`/`copyWith`. `GoalService.markStageAchieved` takes a
  matching optional `achievedBy`. Additive; the field is null when unattributed.
- Fix: `WorkoutAggregation` (`fromRows`/`fromJson`) now buckets weeks and anchors the trailing
  "current week" to the local calendar instead of UTC. West of UTC the old code turned the week over
  at UTC midnight (an empty week appearing on Sunday evening) and filed a Sunday-night session into
  the following week.

## 1.1.0

Changes accumulated on `main` since 1.0.2:

- `ExerciseSet` gains `completedAt`; energy metrics (calories) serialize through
  workout and exercise models.
- Goal visibility extended for cross-user reads.
- Internal: dynamic-call cleanup in `fromJson` paths, generated mocks no longer
  checked in.

## 1.0.2 and earlier

Predate this changelog — see git history of `shared/heart_models`.
