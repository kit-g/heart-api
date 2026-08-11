# Changelog

## 1.2.0

- `GoalService.getTargetUserGoals` gains an optional `archived` flag: `false` (default) returns the
  live goals, `true` returns only the archived ones — the achieved surface behind a completed card.
  Additive; existing callers are unaffected.

## 1.1.0

Changes accumulated on `main` since 1.0.2:

- `ExerciseSet` gains `completedAt`; energy metrics (calories) serialize through
  workout and exercise models.
- Goal visibility extended for cross-user reads.
- Internal: dynamic-call cleanup in `fromJson` paths, generated mocks no longer
  checked in.

## 1.0.2 and earlier

Predate this changelog — see git history of `shared/heart_models`.
