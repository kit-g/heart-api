# Changelog

## 2.39.0

- New: `ExerciseSet.clearMeasurements(Set<ExerciseSetField>)`, with
  `ExerciseSetField` (`weight`, `reps`, `duration`, `distance`): unsets those
  measurements, leaving the others alone, and the set then writes as one
  that never had them. `setMeasurements` still reads a null as "keep" (heart-api#212).
- `ExerciseSet.toRow` always carries the measurements of the set's category,
  a null one included, so an update from it clears a stored value; the
  others stay out, as before.
- New: `WorkoutAggregation.fromRows` and `fromJson` take `firstWeekday` (ISO,
  1 Monday to 7 Sunday), the day its weeks start on; Monday when it is left
  out, so a caller passing nothing gets the weeks it did (heart-api#203).
- Fix: the weeks `WorkoutAggregation` fills in are calendar weeks, so near a
  DST change none lands an hour off midnight and drops the workouts of the
  week it stands for.

## 2.38.0

Suspicious entries and what the user makes of them (heart-api#42).

- New: `Anomaly`, a set or a workout's duration the server's sweep found
  suspicious: why (`reason`, one of `AnomalyReason` or a newer word), what
  was entered (`observed`), and the exercise's `typical` weight.
- New: `AnomalyStatus` (`pending`, `valid`, `invalid`).
- New: `AnomalyService`: list them, resolve one.

## 2.37.0

Primary and secondary work per muscle group, and the muscle map from the body
atlas itself.

- New: `MuscleTagging.primaryGroups`, the groups the primary tags reach: the
  ones `groupShares` counts as primary.
- `MuscleGroupKey.ofMuscle` reads the body map's own grouping from
  `body_atlas` (^0.1.0, pure Dart; what `flutter_body_atlas` 0.2.2 re-exports)
  instead of a copy kept here. Every atlas muscle lands in the group it did.
  New dependency: `body_atlas`.

## 2.36.0

Muscle groups and the user's week, for counts by muscle (heart-api#116).

- New: `MuscleGroupKey`, the ten groups the body map draws (`legs` … `chest`),
  with `tryParse` and `ofMuscle(id)`, the group a library muscle id belongs to
  on either side.
- New: `MuscleTagging.groupShares`, the share of a set each group the tags
  reach receives; a group in both roles counts once, as primary.
- New: `Target.muscleGroup`, the group an untagged exercise falls to.
- New: `Settings.firstWeekday` (ISO, 1 Monday to 7 Sunday), on the wire as
  `firstWeekday`; one out of range reads as null.
- Fix: `MuscleTagging.shareOf` with a group matches the muscles in it, so
  `shareOf('chest')` is 1 for an exercise tagged only `pectoralis_major`.

## 2.35.0

A share of one slot's base (heart-api#257). App side: heart-of-yours#349.

- New: `SetTarget.ofSlot` and `withOfSlot`, on the wire as `ofSlot` beside
  `of`: the template exercise whose base a share is of, when the lift keeps a
  base per slot. `fromJson` reads it, `toMap` writes it, and every `with…`
  keeps it.
- `PlannedSession.of` weighs such a share from that slot's base, else from
  `of`'s own, unless the slot has a rule of its own (`Program.atSlot`).

## 2.34.0

Stages, and rules per slot (heart-api#256). App side: heart-of-yours#350.

- New: `Stages`, a growth rule (`kind: stages`) of two or more `Stage`s
  (`sets`, `reps`, `amrap`), a `step`, and `miss` (moving on the first miss
  by default, also when `miss` gives only its cut) and `amrap` like the
  weighted rules. Exhaustive switches over
  `GrowthRule` gain a case.
- New: `ToStage(stage, base:)`, a `ProgressionStep`. `Progression.next` takes
  `stage` and returns `ToStage(next)` on a miss, or `ToStage(0, base: cut)` on
  the last stage. A stage move needs no base: without one, a miss still
  moves the stage, and the last stage starts over with `base` null. Exhaustive switches over `ProgressionStep` gain a case.
- New: `ProgramActionKind.stage` and `ProgramAction.exercise` / `slot` /
  `stage`; `currentStages(actions)`, keyed like `currentBases`.
- New: `Program.ruleFor(exerciseId, slot:)`. `rules` may also be keyed by a
  slot (a template exercise id), whose rule comes before its exercise's.
- New: `Program.atSlot(byKey, exerciseId, slot:)`, the one lookup of a base or
  a stage: the slot's own, else the exercise's, never that when the slot has
  a rule of its own.
- `PlannedSession.of` takes `stages`, plans a stages rule's sets for its
  stage, and reads a slot's rule, base and stage through `ruleFor` and
  `atSlot`. `PlannedExercise.stage`.

## 2.33.0

A program session as planned (heart-api#260). App side: heart-of-yours#349,
#350.

- New: `PlannedSession.of(program, template, position:, bases:)`, a session's
  sets with this week's targets and the weights worked out from the current
  bases: a `shareOfMax` wave applied to the working sets in order, shares of
  the slot's, the exercise's or `of`'s base rounded down to the rule step, a
  lighter cycle at `deload.load` and `deload.volume`, no weights in a test
  session. `PlannedExercise` (`slot`, `exerciseId`, `base`, `sets`) and
  `PlannedSet` (`setType`, `target`, `weight`, `reps`, `duration`,
  `distance`) carry it, with `toMap` for the developer API and MCP.
- `Progression` rounds the same way through a shared helper; no change in what
  it returns.

## 2.32.0

Phases and test sessions (heart-api#233). App side: heart-of-yours#346, #350.

- New: `ProgramPhase` (`name`, `sessions`, `cycles`) and `Program.phases`; a
  program week falls in a phase by the phases' cycles in turn, the last (or
  one without cycles) taking the rest: `Program.phaseOf(week)`.
- New: `ProgramTest` (`share`) and `Program.tests`, by template id: a workout
  of a test session sets bases through `Progression.test`.
- New: `ProgramPosition.phase`, on the wire as `phase`; `remaining` and `next`
  come from the phase's sessions, or from every session when none of the
  phase's are left, so a deleted session never stalls a week. `week` stays the
  whole program's.
- New: `ProgramField.phases` / `tests` for `without`.

## 2.31.0

Variation ladders (heart-api#231). App side: heart-of-yours#350.

- New: `Ladder`, a growth rule (`kind: ladder`) of `rungs` (exercise ids,
  easiest first), `top` and `bottom`; `after(exercise)`. `Progression.next`
  returns `Advance(nextRung)` once every working set reaches `top`. Exhaustive
  switches over `GrowthRule` gain a case.
- New: `ProgramActionKind.advance` and `ProgramAction.from` / `to` /
  `workoutId`: the swap a ladder made, and what caused it.

## 2.30.0

Lighter weeks (heart-api#229). App side: heart-of-yours#350, #346.

- New: `Deload` (`every` cycles, `load` and `volume` shares) and
  `Program.deload`, on the wire as `deload`; `ProgramField.deload` for
  `without`.
- New: `ProgramActionKind.lighter`: the open cycle becomes a lighter one, on
  demand. An exhaustive switch over the kinds gains a case.
- New: `ProgramPosition.lighter`, on the wire as `lighter`: the open cycle is
  scheduled lighter or asked for. Pass it to `Progression.next`.

## 2.29.0

The progression engine: what a session does to a base, misses, and a step set
by the AMRAP set (heart-api#228). App side: heart-of-yours#350.

- New: `Progression.next(rule:, base:, sets:, misses:, lighter:, week:,
  closesCycle:)` returns a sealed `ProgressionStep`: `Grow`, `Hold`, `Missed`,
  `Cut` or `Advance`. `Progression.streak(rule, sessions, lighter:)` folds the
  misses in a row, skipping sessions of a lighter week; `Progression.test` sets
  a base from a test session (Brzycki, 10 reps at most). `Longer` grows the
  measure the set's target names (distance or duration).
- New: `MissRule` (`when`: `MissWhen.anySet` / `amrap` / `totalReps`, `floor`,
  `after`, `cut`) and `AmrapStep` (`reps`, `step`). `AddWeight` and
  `RangeThenWeight` take `miss` and `amrap`; `ShareOfMax` takes them too and
  reads its `misses` / `missCut` as its miss rule. `GrowthRule.miss` and
  `.amrap` read them for any rule.
- New: `GrowthRule.extra` keeps fields a build doesn't know and writes them
  back. The rule constructors gain an optional `extra`.
- New: `ShareOfMax.closesWave(week)`.
- New: `SetTarget.supplemental`, on the wire as `supplemental: true`: a set the
  engine leaves out.

## 2.28.0

Slots: one lift with two bases, a share of another's, supplemental sets and
open slots (heart-api#232). App side: heart-of-yours#349, #346.

- New: `ProgramBase.slot`, the template exercise a base belongs to when one
  lift has two. `currentBases` now keys a slotted base by its slot, and the
  rest by exercise id as before.
- New: `SetTarget.of` / `withOf`: whose base `share` is a share of, on the
  wire as `of`. Null is the set's own exercise.
- New: `WaveSet.supplemental`: takes its share but never counts for the AMRAP,
  a miss or a bump.
- New: `WorkoutExercise.pattern` (an open slot: any exercise of a movement
  pattern) and `WorkoutExercise.totalReps` (reps across all sets), on the wire
  as `pattern` / `totalReps`, carried into workouts like `rest` and cleared
  like it (`toMap` sends a null once the key was read or assigned). A
  `totalReps` in a shape this build predates is carried as it came, never a
  failed read.
- New: `TemplateExerciseRequest.pattern` / `setsPattern` and `totalReps` /
  `setsTotalReps`, three-valued.

## 2.27.0

Supersets and circuits (heart-api#234). App side: heart-of-yours#159.

- New: `WorkoutExercise.superset`, the superset an exercise belongs to in its
  session (same number, back to back), on the wire as `superset`. Carried by
  `Template.toWorkout` and both kinds of `Workout.copy`. Cleared like `rest`:
  `toMap` sends `superset: null` once it was read or assigned.
- New: `TemplateExerciseRequest.superset` / `setsSuperset`, three-valued.

## 2.26.0

Effort targets, a capped AMRAP, and rest per exercise (heart-api#230). App side:
heart-of-yours#349.

- New: `SetTarget.rir` and `withRir`, reps in reserve, on the wire as `rir`
  beside the measures. `SetTarget`'s factory takes it.
- New: `TargetRange.amrap`, as many as possible up to `max`, on the wire as
  `amrap: true` in a bounded range; `isAmrap` is true for it and for an open
  top. A range's equality now includes it.
- New: `WorkoutExercise.rest`, seconds between sets as a template plans it, on
  the wire as `rest`; `Template.toWorkout` and `Workout.copy` carry it.
  `toMap` sends `rest: null` once it was read or assigned, so clearing it
  clears the server's; an exercise that never had the key leaves it out.
- New: `TemplateExerciseRequest.rest` / `setsRest`, three-valued like a set's
  target.

## 2.25.0

A history move re-keys programs (heart-api#226). App side: heart-of-yours#346.

- New: `ExerciseMoveReport.programs`, the programs whose rules or bases moved
  from the source to the target, on the wire as `programs`. Optional in the
  factory and read as 0 when absent.

## 2.24.0

Four gaps the app ran into (heart-api#227). App side: heart-of-yours#346.

- New: `Program.without({ProgramField...})` unsets `note`, `perWeek`, `weeks`
  or `constraint`, which `copyWith` can't (a null there keeps the value).
- New: `Program.joined`, when each session joined the program, on the wire as
  `joined` (template id → ISO time). `ProgramPosition.of` reads it before the
  id's own time, so a template filed into a program later joins when it was
  filed.
- New: `Template.joined` and `TemplateRequest.joined`, when the session
  joined its program as the device saw it, on the wire as `joined`. Send it
  when filing a session into a program: one filed offline then joins when it
  was filed, not when it synced. Without it the server stamps its own clock.
- New: `ProgramPosition.target`, what `thisWeek` counts toward: the weekly
  target, or null while paused or finished. `thisWeek` itself stays a count.

## 2.23.0

Where the user stands in a program, computed the same everywhere
(heart-api#217, part of heart-api#86).

- New: `ProgramPosition.of(program, marks:, actions:, now:, firstWeekday:)`, a
  pure fold: `week`, `done`, `remaining`, `next`, `paused`, `finished`,
  `thisWeek`. The rules are on the factory; the design is
  `docs/2026-10-13.programs.md` in heart-api.
- New: `ProgramMark` (`workout`, `skip`), what the fold reads beside the
  program's actions.
- New: `currentBases`, the latest base per exercise.
- New: `SetTarget.share` and `withShare`, a set's weight as a share of the
  exercise's base, on the wire as `share`. Builds since 2.16.0 already carried
  the key untouched.

## 2.22.0

Skips, and programs in the account summary (heart-api#202).

- New: `TrainingSkip` ("Not today"): `id`, `at`, `reason` (a snake_case tag),
  `weather`, `templateId`, `programId`. Named so it doesn't collide with
  `package:test`'s `Skip`.
- New: `Weather` (`temperature` °C, `humidity` %, `pressure` hPa,
  `pressureTrend` hPa over 24 h), read tolerantly: an unknown field is kept
  and written back.
- New: `ExportableCollection.programs`, `programActions`, `programBases` and
  `skips`, in upsync replay order. Exhaustive switches over the enum gain
  these four cases; `tryParse` and the summary's reader were already tolerant.

## 2.21.0

Program actions and bases (heart-api#216, part of heart-api#86).

- New: `ProgramAction` (`id`, `programId`, `kind`, `week`, `at`) and
  `ProgramActionKind`: `repeat`, `pause`, `resume`, `replay`. An unknown kind
  is an `ArgumentError`, so `readEach` sets it aside.
- New: `ProgramBase` (`id`, `programId`, `exerciseId`, `value`, `workoutId`,
  `actionId`, `at`, `isManual`): one value of what an exercise's growth rule
  grows, with its cause.

## 2.20.0

Workouts name the template and the program they were started from
(heart-api#215, part of heart-api#86).

- New: `Workout.templateId` and `Workout.programId`, on the wire as
  `templateId` / `programId` and on the row as `template_id` / `program_id`;
  left out of `toMap` when null, so a save never detaches a workout.
- New: optional `templateId` and `programId` on `Workout.fromExercises`.
- `Template.toWorkout` now sets both from the template. `Workout.copy` keeps
  them for the same session and drops them for a repeat.

## 2.19.0

Programs: the entity and its sessions (heart-api#214, part of heart-api#86).

- New: `Program`, a plan of the user's templates: `name`, `note`, `source`
  (the library program it was copied from), `perWeek`, `days`, `weeks`,
  `rules`, `constraint`, `archived`, `sessions` (its template ids, in order)
  and `createdAt`. `fromJson`, `fromRow`, `toMap`, `copyWith`.
- New: `GrowthRule`, sealed: `NoGrowth`, `AddWeight`, `RangeThenWeight`,
  `Longer` and `ShareOfMax` (with `WaveSet`). `fromJson` is strict;
  `Program` reads a rule it doesn't know into `unreadRules` and writes it back.
- New: `Template.programId` and `Template.note`, on the wire as `programId` /
  `note` and on the row as `program_id` / `note`; left out when null.
- New: `TemplateRequest.programId` / `movesProgram` and `note` /
  `changesNote`, three-valued like `folderId`.

## 2.18.0

Goals about a movement pattern or a muscle (heart-api#196).

- New: `GoalMetric.sessions` (workouts that trained the subject) and
  `GoalMetric.sets` (working sets on it, fractional for a muscle), with
  `GoalMetric.countsSubject`. Neither has a `chart`. Exhaustive switches over
  `GoalMetric` gain these two cases.
- New: `Goal.pattern` (a library pattern key) and `Goal.muscle` (a muscle id
  prefix or group), on the wire and the row as `pattern` / `muscle`, in the
  factory, `copyWith`, `toMap` and `toBody`; left out when null.
- New: `Goal.subject`, a sealed `GoalSubject`: `ExerciseSubject`,
  `PatternSubject` or `MuscleSubject`.

## 2.17.0

How much of a set each muscle receives (heart-api#197).

- New: `MuscleTag.share`, a role's own share of a set when the library gives
  one; read from and written to `share`, left out when null.
- New: `MuscleTagging.primaryShare` and `secondaryShare` (defaults
  `MuscleTagging.defaultPrimaryShare` 1.0 and `defaultSecondaryShare` 0.5),
  and `shareOf(muscle)`: the share of one set a muscle id prefix or group
  receives, primary first, 0 when untagged.

## 2.16.0

Targets on template sets (heart-api#195, heart-of-yours#173).

- New: `SetTarget`, what a template set aims for per `TargetMeasure` (`reps`,
  `weight`, `duration`, `distance`), each a `TargetRange`: `min` and an
  optional `max`, exact when they are equal (`TargetRange.exactly`), an open
  top ("8+") when `max` is null. `fromJson`/`toMap`, `operator []`,
  `withRange`, `isEmpty`, and `SetTarget.none`. A measure or a range shape this
  build doesn't know is carried as it arrived and written back.
- New: `ExerciseSet.target` and the factory's `target:`. Read off a set's
  `target` key; `toMap` writes the key only on a set that arrived with it or
  had one assigned, and there always, null included, so a target can be
  cleared. `copy()` keeps it.
- New: `TemplateSetRequest.target`: null leaves the stored target alone,
  `SetTarget.none` clears it.

## 2.15.0

Moving an exercise's history onto another exercise (heart-api#140, heart-of-yours#338).

- New: `ExerciseMoveReport`, the answer of `POST /exercises/:exerciseId/moves`:
  `sourceId`, `targetId`, `dryRun`, the counts `workoutExercises`,
  `templateExercises`, `preferences`, `preferencesDropped`, `chartPreferences`,
  `goals`, and `sourceDeleted`; `fromJson`/`toMap` (every field required), and
  `fromRow` over the database function's row with the ids and the mode passed in.

## 2.14.0

Connected apps for the OAuth authorization server (heart-api#115).

- New: `ConnectedApp`, an app the account approved through OAuth: `id`,
  `clientId`, `name` (as shown on consent), `scopes`, `resource`,
  `connectedAt`, `lastUsedAt`; `fromJson`/`toMap`, and `fromRow` over an
  `oauth_grants` row.

## 2.13.0

A session's chart values as shared code (heart-api#116).

- New: `List<RecordSet>.toSessionMetrics(Category)` (extension
  `SessionMetrics`), one session of one exercise as the values its progress
  chart plots, keyed by `ChartPreferenceType.value`: only the dimensions
  `chartsByExerciseCategory` lists for the category, each present only when
  the sets measure it. The definitions are the app's chart queries, with one
  difference: `estimatedOneRepMax` leaves out sets past 36 reps, where the
  Brzycki denominator crosses zero, as `toPersonalRecords` does.

## 2.12.0

Personal records as shared code (heart-api#114).

- New: `List<RecordSet>.toPersonalRecords(Category)` (extension
  `PersonalRecords`), one exercise's personal records from its completed,
  non-warm-up sets, oldest first: per category
  `heaviest`, `oneRepMax` (Brzycki), `bestVolume`, `repMaxes`, `mostReps`,
  `lightestAssistance`, `longestDistance`, `longestDuration`, `bestPace`,
  totals, `sessions` and `firstAt`; each headline record carries the set it
  happened on and `previous`, what it beat. Ties keep the earlier set. Null
  when nothing was ever measured.
- New: `RecordSet`, the fold's input (`weight`, `reps`, `duration`,
  `distance`, `workoutId`, `at`), with `fromRow` for `workout_id`/`start`
  rows.

The app's local-database fold, moved here so records read the same wherever
they are computed, with two fixes over that copy: `totalVolume` is reported
for any set with weight and reps, not only when a rep max (≤ 10 reps)
exists; and `previous` folds only the sessions before the record's own, so a
record never "beats" a set that came after it.

## 2.11.0

Reads survive a value this build doesn't know (heart-api#125,
heart-of-yours#277): an app in the stores keeps working when the server or the
CDN adds a category, a set type, a metric or the like, and never deletes or
rewrites what it could not read.

- New: `readEach(items, read)` and `ReadList<T>`, a list read item by item;
  the items `read` rejects (`ArgumentError`, `TypeError`, `FormatException`)
  are set aside in `unread` instead of failing the list. For the lists a
  client parses itself: the library, workouts, templates, goals, preferences.
- New: `Workout.unread`, `Template.unread`, `WorkoutExercise.unread` — the
  exercises or sets this build could not read, as they arrived. `fromJson`
  and `fromRow` set them aside instead of failing; `toMap` writes them back in
  place (a workout's with a fresh unique `order`), so a save carries them
  untouched. A fresh-id `Workout.copy` and `Template.toWorkout` leave them
  behind. An exercise whose only sets are unread is kept by `Workout.toMap`
  and `removeEmptySets`.
- Changed: `Workout.copy(sameId: true)` is the same session as it is — every
  exercise and set keeps its id, order, state and rating, and every exercise
  and set this build could not read comes along (heart-api#131). A fresh-id
  copy is unchanged: a repeat with new ids, unrated, readable items only.
  `ExerciseSet.copy` gains `sameId` for the same purpose.
- New: `ExerciseSet.setTypeValue`, the `set_type` word a write carries. A set
  with a type this build doesn't know still reads as `normal` (as before), but
  `toMap` and `copy` now carry the original word instead of rewriting it as
  `normal`; assigning `setType` replaces it. Writers that store a set's type
  keep this word.
- Changed: `Movement.fromJson` reads an unrecognised attribute word as
  `Movement.empty()` (no substitutes, no movement filter matched) and
  `Health.fromJson` an unrecognised activity as none (`resolve` falls back by
  category), instead of throwing. Absent keys read as before.

The `fromString` parsers stay strict: they are what the server validates
input with.

## 2.10.0

Domain rules the app kept as its own extensions (heart-api#126), so the
server and every client get the same answer.

- New: `Category.isTimed`, the categories whose sets hold a time (Duration,
  Cardio, Weighted Duration).
- New: `Category.distanceScale` and `DistanceScale` (`short`: metres or
  yards; `long`: kilometres or miles). Weighted Distance reads short; storage
  stays in kilometres.
- New: `Movement.distanceTo(Movement)`, the substitute ranking: the sum of
  gaps on axial load, impact and skill plus a flat mismatch on stability and
  unilateral. Only the order is meaningful.
- New: `MovementFilter` with `PatternFilter`, `SkillCeiling` and
  `StabilityFilter`; `Exercise.matchesMovement(filters)`, and `Exercise.fits`
  now applies the movement dimensions too. An exercise with no movement
  annotation never matches an active movement filter.
- New: `Goal.toBody()`, the create/replace request body — metric,
  exerciseId, cadence, archived, stages with their ids; never `id` or
  `createdAt`.
- New: `WorkoutAggregation.workoutCount`, workouts rather than weeks.
- New: `ChartPreferenceType.periodAggregate` and `PeriodAggregate`
  (`sum`/`best`/`mean`, with `of(values)`): how a dimension's sessions fold
  into one number for a recurring goal.
- New: `ChartPreferenceType.isDuration` (cardio duration, time under tension).
- New: `Iterable<Exercise>.byId`.

## 2.9.0

Personal access tokens for the developer API (heart-api#111; app side
heart-of-yours#271).

- New: `ApiToken`, a token as its owner lists it: `id`, `name`, optional
  `purpose`, `hint` (the secret's last four characters), `scopes`,
  `createdAt`, `lastUsedAt`, `expiresAt` (null until revoked), `revokedAt`,
  and `isActive()`. `ApiToken.maxActive` (5) and `maxNameLength` (100).
- New: `MintedApiToken`, the create response: the token's fields plus
  `secret`, the plaintext shown only once.
- New: `ApiTokenPurpose` (`script`, `spreadsheet`, `homeAutomation`,
  `aiAssistant`, `other`) and `ApiTokenExpiry` (`year`, `never`).

## 2.8.0

Exercise search vocabulary (heart-api#102; app side heart-of-yours#135).

- New: `Exercise.aliases`, the other names lifters search an exercise by in
  the served locale (`ohp`, `skull crusher`); wire key `aliases`, empty for
  user-created exercises, round-trips through `fromJson`/`toMap`.
- New: `SearchGlossary` (with `SearchTerm`), a locale's search vocabulary:
  abbreviations (`db` → dumbbell) and muscle words (`lats` → a muscle id
  prefix or group), parsed from the `glossary` the library now publishes
  beside `exercises`.
- New: `Exercise.match(query, glossary:)` reports how a query matched, as a
  `SearchMatch` tier ranked best first: `prefix`, `words`, `vocabulary`
  (only through an alias or the glossary), `typo` (one edit, words of 4+
  letters); null when it doesn't. Accent- and case-insensitive. `contains`
  is unchanged.

## 2.7.0

Loaded carries and holds get their own categories (heart-api#85; app side
heart-of-yours#253).

- New: `Category.weightedDistance` (`Weighted Distance`: weight and distance,
  e.g. farmer's carry, sled push) and `Category.weightedDuration`
  (`Weighted Duration`: weight and duration, e.g. weighted plank).
- `ExerciseSet` keeps `weight`+`distance` and `weight`+`duration` for them
  respectively; `canBeCompleted` needs both. `total`, which `best` ranks by,
  is weight × distance (kg·km) and weight × seconds.
- `chartsByExerciseCategory`: `topSetWeight` + `cardioDistance` for weighted
  distance, `topSetWeight` + `totalTimeUnderTension` for weighted duration.
- Neither switches to or from another category (`canSwitchTo`).

## 2.6.0

Workout pauses reach the wire (heart-api#95; app side heart-of-yours#134).

- New: `WorkoutPause` (`start`, `end`, `duration`), written as UTC ISO
  instants under `start`/`end`.
- New: `Workout.pauses` (`List<WorkoutPause>`, mutable, empty when none) and
  `Workout.maxPauses` (100), read from `pauses` on server rows and local JSON.
  Absent reads as none. The list holds closed pauses only: an active
  workout's open pause is app state until it is closed.
- Changed: `Workout.duration` is `end − start − Σ pauses`, and `elapsed()`
  leaves closed pauses out. `start` and `end` are never moved.
- Changed: `Workout.copy(sameId: true)` keeps the pauses (as its own list), and
  a repeat with a fresh id drops them.
- The server checks what it stores: each pause has `start < end`, lies within
  the workout's `start..end` (only after `start` while `end` is null), and
  pauses don't overlap. Touching ends are fine. Anything else is a `400`. A
  save that moves `start` or `end` without a `pauses` key clips the stored
  pauses to the new window and drops any left empty.
- **App must, before shipping a build on this version:** `Workout.toMap` now
  always writes `pauses`, an empty list included, and the server treats a
  present key as the new value. So the local mirror has to keep pauses on
  every write path, or a workout re-saved from the mirror clears pauses
  recorded on another device.

## 2.5.0

Set types, RPE and the workout note reach the app (heart-api#83; app side
heart-of-yours#151). The server has stored them since heart-api#84, from
Strong imports.

- New: `SetType` (`normal`, `warmup`, `drop`, `failure`; wire word in
  `value`). `fromString` reads absent or null as `normal` and throws on an
  unknown word. `lenient`, which `ExerciseSet.fromJson` uses, reads an
  unknown word as `normal`, so a type added later never fails a read.
- New: `ExerciseSet.setType` (defaults to `normal`) and `ExerciseSet.rpe`
  (`double?`, 1–10 in half steps), read from `set_type`/`rpe`. The
  constructor takes both.
- New: `Workout.note` (`String?`) and `Workout.maxNoteLength` (1000), read
  from `note` on server rows and local JSON.
- New: `TemplateExerciseRequest.id`, `TemplateSetRequest.id` and
  `TemplateSetRequest.setType`. Template exercises and sets now keep their ids
  across saves. A null `setType` leaves a stored type alone, and
  `SetType.normal` clears it.
- Changed: `WorkoutExercise.best` and `WorkoutExercise.total` (and so
  `Workout.total`) leave warm-ups out. Drop and failure sets count as before.
- Changed: `ExerciseSet.copy` keeps the set type and drops the RPE.
  `Workout.copy(sameId: true)` keeps both RPE and note, and a repeat with a
  fresh id drops them.
- **App must, before shipping a build on this version:** `ExerciseSet.toMap`
  now always writes `set_type` and `rpe`, and `Workout.toMap` always writes
  `note`, null included. The server treats a present key as the new value.
  `toRow` is unchanged, because a new key there breaks the local inserts. So
  the local mirror has to gain columns for all three, or a workout re-saved
  from the mirror clears imported warm-ups, RPEs and notes.

## 2.4.0

Gives account deletion what it needs to revoke a Sign in with Apple grant, so
an account deleted through the app stops being listed under the user's Apple ID
(heart-api#78).

- New: `AppleDeletionGrant` — `{authorizationCode, clientId}`, serialised as
  `{appleAuthorizationCode, appleClientId}`. The code is single-use and expires
  within minutes; the server spends it at once for a long-lived token and
  revokes that when the deletion schedule fires.
- Changed: `AccountService.deleteAccount` takes an optional `appleGrant`.
  **Implementers must add the parameter** — it is optional to callers, not to
  the class that implements the interface. Google and password accounts pass
  nothing and delete exactly as before.

## 2.3.0

Adds the pinned note — a note the user attaches to an exercise once, rather than
to a single session.

- New: `ExercisePreference.note` (`String?`) and `ExercisePreference.maxNoteLength`
  (200) — a third optional field on the `{exerciseId, unitSystem?, restTimer?}`
  body and response of `/exercise-preferences`, parsed and emitted beside the
  other two. `fromJson` trims it, reads blank as no note, and throws
  `ArgumentError` past the cap or on a non-string.
- New: `ExercisePreferenceField.note`, the `?pref=note` wire value.

## 2.2.0

Gives the app a way to know its local mirror is complete before it exports —
the gap that showed up building anonymous accounts, where the device is the
only place the data has ever lived.

- New: `AccountSummary`, `CollectionSummary` and `ExportableCollection` — the
  body of `GET /accounts/summary`, a per-collection row count plus the newest
  row's id. The device compares them against its own tables; a matching count
  with a different `latestId` is a divergence a count alone reads as in sync.
  `ExportableCollection.tryParse` returns `null` for a key this build does not
  know, and `AccountSummary.fromJson` skips those, so an app lagging a server
  that added a collection still parses.

## 2.1.0

Supports the anonymous-to-account upsync replay (heart-api#66): the app's
local-first writes become idempotent on the client's own id when replayed into
a real account.

- New: `TemplateRequest.id` — the template's client-minted id, optional, read
  on create so a replayed `POST /templates` lands on the same row instead of a
  duplicate. Nothing else in the package changes; the created-vs-existing
  signal the API needs lives in API-only sub-interfaces (`api/lib/models/creates.dart`).

## 2.0.0

Exercise identity moves from the name to the uuid — a coordinated breaking release for the
stable-keys cutover (the app must adopt this in lockstep; the API's name-based lookups are gone).

- **Breaking**: `Exercise.id` is non-nullable and is the identity — `==`/`hashCode` compare ids,
  and `fromJson` throws on a payload without one. Two locales' views of the same exercise now
  compare equal; the factory still mints a client-side UUIDv7, which the server persists on
  create, so offline-created customs keep their identity through sync.
- **Breaking**: `TemplateExerciseRequest.exerciseName` is now `exerciseId`, serialized as
  `exercise_id` — the only reference the template SQL resolves.
- New: `Exercise.key` — the env-stable content slug (`bench-press-barbell`) for library
  exercises, `null` for user-created ones. A content/fixture handle, not a wire reference.
- `Exercise.name` is localized display copy, never an identifier.
- New: `isUuidV7` — the shared shape predicate for platform ids, now public so the API and the
  app validate client-minted ids against one definition instead of private copies.
- Search (`Exercise.contains`) normalization is unicode-aware, so Cyrillic/accented display
  names match; the slug also matches, so the canonical English wording keeps working under any
  locale.

## 1.9.0

Surfaces the exercise library's copy-provenance flag, so the client can be explicit about
machine-authored copy (a spark icon in the exercise library).

- New: `Exercise.validated` — whether a human has reviewed the exercise's copy (name and
  instructions) for the served locale. `false` marks machine-authored library copy to label;
  `null` means there is no library-managed copy to take a stance on (user-created exercises).
  Server-owned: `copyWith` carries it, nothing client-side mutates it. Local round-trip stores
  it as 1/0 next to `own`/`archived`.

## 1.8.0

Carries the health activity type in the exercise library (heart-api#54), replacing the
app's name-based activity switch — `Exercise.name` is localized copy and must never key logic.

- New: `HealthActivity` — the canonical, platform-neutral activity a session is written to
  HealthKit / Health Connect as (camelCase wire values, matching the DB blob). Session-level
  `crossTraining`/`mixedCardio` are deliberately absent: the client derives them.
- New: `Health` on `Exercise` — optional like `movement`, empty for most exercises and all
  user-created ones. `Health.resolve(Category)` carries the fallback (`Cardio`/`Duration` →
  `other`, everything else → `strength`), and `Exercise.activity` reads annotation-or-fallback,
  so a custom cardio exercise never resolves to strength training.

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
