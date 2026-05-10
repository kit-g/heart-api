## Heart Models

Shared domain models and service interfaces for the Heart project. This package defines the core data types (User, Exercise, Workout, Template, etc.) and the service contracts they interact with (accounts, workouts, templates, exercises, feedback, config, stats, timers). It is intentionally framework‑agnostic and contains no networking or UI code.

### Why this package exists
- A single source of truth for domain shapes used across app features and services.
- Decouples data modeling from transport. HTTP clients (e.g., heart_api) implement the Remote* service interfaces without leaking HTTP details into the app.
- Improves testability: services can be mocked against the same interfaces; models are plain, predictable objects.
- Encourages consistency in serialization, comparison, and ID generation across the app.

### What it includes
- Models (pure data objects)
  - User, Exercise, ExerciseSet, ExerciseAct, Workout, Template
  - Aggregations and summaries (WeekSummary, WorkoutSummary, WorkoutAggregation)
  - Small helpers and mixins: UsesTimestampForId, Searchable, Storable, Model
  - Errors: AccountDeleted
- Service interfaces (no implementations here)
  - Accounts, Exercises, PreviousExercise, Workouts, Templates, Stats, Feedback
  - Config (remote configuration), Timers
  - Each service focuses on behavior and types, leaving I/O to other packages
- A single export: package:heart_models/heart_models.dart collects all public APIs

### Design notes
- Interfaces first: almost all public types are abstract interfaces with factory constructors that return private implementations. This keeps the surface area small while allowing construction via factories like User(...), Workout(...), etc.
- JSON-friendly: models provide toMap and factory constructors like fromJson(Map) where applicable, using simple Map and primitive types.
- Immutable by default: fields are final in concrete implementations; copyWith is provided where mutation semantics are needed.
- ID strategy: UsesTimestampForId mixin offers consistent, comparable identifiers derived from timestamps for sets/workouts.
- No transport/runtime coupling: there are no imports from http, Flutter, or platform APIs; suitable for pure Dart and Flutter.

### Quick start
- Add a dependency within the monorepo and import the umbrella library:

  ```dart
  import 'package:heart_models/heart_models.dart';

  // Create models using factories
  final user = User(id: 'u1', displayName: 'Jane Doe', email: 'jane@example.com');

  // Build an Exercise from JSON and use it in a Set
  final pushUp = Exercise.fromJson({
    'name': 'Push-up',
    'category': 'Reps Only',
    'target': 'Chest',
  });

  final set1 = ExerciseSet(
    pushUp,
    reps: 10,
  )..isCompleted = true;

  // Create a Workout and add the exercise with the starter set
  final workout = Workout(name: 'Morning');
  final ex = workout.add(pushUp);
  ex.add(set1);
  ```

- Program to interfaces in your app code; let an implementation (e.g., from heart_api) fulfill the Remote* contracts:

  ```dart
  // Example service contract usage
  Future<void> loadWorkouts(RemoteWorkoutService api, ExerciseLookup lookup) async {
    final items = await api.getWorkouts(lookup, pageSize: 20);
    // Render or store items
  }
  ```

### Relationship to heart_api
- heart_models defines the data and contracts.
- heart_api implements a subset of Remote* services (accounts, templates, workouts, feedback, exercises, config) over HTTP.
- This separation keeps your domain logic unit-testable without networking and allows swapping transport layers in the future.

### Source overview
- lib/heart_models.dart: barrel export for all public types
- src/models/: data objects and helpers
  - auth.dart (User), exercise.dart, exercise_set.dart, act.dart, workout.dart, template.dart
  - stats.dart (summaries), misc.dart (traits), ts_for_id.dart, errors.dart, utils.dart
- src/services/: abstract interfaces for accounts, config, exercises, feedback, previous, stats, templates, timers, workout

### Versioning and compatibility
- Dart SDK: see pubspec (currently ^3.5.4)
- No Flutter runtime dependency; usable in pure Dart and Flutter packages.

### Testing
- Because all types are plain Dart, you can instantiate them directly or use the interfaces with mocks (e.g., mockito) in unit tests.

### Installation
This package is part of the Heart monorepo and is not published to pub.dev (publish_to: none). Depend on it via path or workspace resolution within this repository.

### License and contributions
This package is internal to the Heart project. Issues and contributions should be made in this repository.
