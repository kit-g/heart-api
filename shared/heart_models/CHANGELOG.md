# Changelog

## 1.7.0

- New: `Template.createdAt` — the template's creation instant, recovered from the id rather than
  stored or synced. Server template ids are v7 uuids minted by the same insert that stamps the
  row's `created_at`, so the value agrees with the server column to the millisecond.

## 1.6.0

Retires the Firebase-era practice of using start timestamps as ids (and staggering copies by a few
milliseconds to keep them unique).

- `ExerciseSet` ids are now client-minted v7 uuids instead of the start's ISO string. `fromJson`
  still honors an id it is given, so legacy timestamp ids survive as opaque strings; equality stays
  id-based and ordering stays by `start`. The internal `UsesTimestampForId` mixin (never exported)
  is deleted — `ExerciseSet` keeps its whole surface (`id`, `start`, `elapsed()`, `Comparable`).
  The server never stores client set ids (it re-mints them on every save), so nothing changes on
  the wire.
- `Workout.copy()` and `Template.toWorkout()` no longer stagger copied sets' starts by 2 ms per
  set — that existed only to keep timestamp-ids unique, and it polluted `started_at` with fake
  offsets.
- New: `timestampOfUuidV7(String)` — the mint instant embedded in a v7 uuid's leading 48 bits, or
  null for anything else.
- `WorkoutImage.timestamp` and `ExerciseAct.start` were still recovering a date by parsing the id
  as a (sanitized) timestamp — always null since ids became uuids. Both now fall back to
  `timestampOfUuidV7`, so either era's id yields the instant.
- Week keys in `WorkoutAggregation` are written as plain ISO strings; the Firebase `.`→`_`
  escaping is gone from the write path. Readers still go through `deSanitizeId`, which accepts
  both forms, so cached legacy keys keep parsing. `sanitizeId` is deprecated (reader-side
  `deSanitizeId` stays).
- `WorkoutAggregation.dummy()` mints uuid workout ids instead of hour-shifted timestamps.

## 1.5.1

- `ExerciseSet` construction is now category-aware: only the measurements that exist for the
  exercise's category are kept (weight/reps for weighted categories, reps for reps-only,
  duration/distance for cardio, duration for timed holds), mirroring `setMeasurements`. Legacy
  device-DB rows carry zero-valued `duration`/`distance` written by an old serializer
  ([#51](https://github.com/kit-g/heart-api/issues/51)); `fromJson` used to keep them verbatim and
  `toMap`/`toRow` re-emitted them forever. They are now dropped on construction, so the junk heals
  on the next round trip. No wire-format change for clean data — inapplicable fields were already
  omitted when null.

## 1.5.0

- `Template` gains `copyWith({required TemplateFolder? folder})` — an identical template filed
  under the given folder, or unfiled when passed null. Replaces the app's `toMap`/`fromJson`
  round trip for optimistic filing (`heart_state` `_filed`), which silently depended on the two
  staying symmetric. `folder` is required on purpose: null means "unfile", so there is no absent
  value for a default to mean. `toMap()` still omits `folder`/`folderId` when unfiled — the
  wire format is unchanged. Additive.

## 1.4.0

- `RemoteWorkoutService` gains `getTargetWorkout({requesterId, targetUserId, workoutId})` — a single
  server-side workout read, matching `GoalService.getTargetUserGoals`'s visibility model (owner or an
  active COACH/PEER, else `Forbidden`). Returns a non-null `Workout`; a missing one is `NotFound`, so
  the client can tell "gone" (`not_found`) from "not in the local mirror yet". Unblocks deep links and
  viewing a connection's workout on clients without a warm history (notably web). The API side already
  exists (`GET /accounts/:targetUserId/workouts/:workoutId`); this only declares the client's call.
  Additive.

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
