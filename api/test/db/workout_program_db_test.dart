@Tags(['db'])
library;

import 'package:heart/models/workouts.dart';
import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

import 'db_test_utility.dart';

/// A workout's template and program (heart-api#215): stored when the caller
/// owns them, kept when a body leaves them out, and let go when what they name
/// is deleted. Tagged `db`.
void main() {
  final h = _Harness();

  late String userId;
  late String strangerId;

  String imageUrl(String key) => key;

  WorkoutRequest body(Map<String, dynamic> links) {
    return WorkoutRequest(
      userId: userId,
      body: {
        'name': 'Session A',
        'start': DateTime.utc(2026, 10, 14, 18).toIso8601String(),
        'end': DateTime.utc(2026, 10, 14, 19).toIso8601String(),
        ...links,
      },
    );
  }

  /// A program with one session, returning both ids.
  Future<(String program, String template)> seedProgram(String owner) async {
    final (program, _) = await h.db.createProgramOrExisting(
      userId: owner,
      program: Program(name: 'Getting stronger'),
      sessions: [TemplateRequest(userId: owner, name: 'A')],
    );
    return (program.id!, program.sessions.single);
  }

  setUpAll(() async {
    await h.setupDatabase();
    userId = await h.seedProfile();
    strangerId = await h.seedProfile();
  });

  tearDownAll(h.teardownDatabase);

  test('a workout started from a session names it and its program', () async {
    final (program, template) = await seedProgram(userId);

    final (workout, _) = await h.db.createWorkout(
      userId: userId,
      body: body({'templateId': template, 'programId': program}),
      imageUrl: imageUrl,
    );

    expect(workout.templateId, template);
    expect(workout.programId, program);
    final read = await h.db.getWorkout(userId: userId, workoutId: workout.id, imageUrl: imageUrl);
    expect((read.templateId, read.programId), (template, program));
  });

  test("someone else's template or program, or no id at all, saves the workout unlinked", () async {
    final (program, template) = await seedProgram(strangerId);

    final (theirs, _) = await h.db.createWorkout(
      userId: userId,
      body: body({'templateId': template, 'programId': program}),
      imageUrl: imageUrl,
    );
    expect(theirs.templateId, isNull);
    expect(theirs.programId, isNull);

    final (garbage, _) = await h.db.createWorkout(
      userId: userId,
      body: body({'templateId': '1700000000000', 'programId': 42}),
      imageUrl: imageUrl,
    );
    expect(garbage.templateId, isNull);
  });

  test('a replace without the keys keeps them, as a 1.13 save does; null lets go', () async {
    final (program, template) = await seedProgram(userId);
    final (workout, _) = await h.db.createWorkout(
      userId: userId,
      body: body({'templateId': template, 'programId': program}),
      imageUrl: imageUrl,
    );

    final kept = await h.db.updateWorkout(userId: userId, workoutId: workout.id, body: body({}), imageUrl: imageUrl);
    expect((kept.templateId, kept.programId), (template, program));

    final cleared = await h.db.updateWorkout(
      userId: userId,
      workoutId: workout.id,
      body: body({'templateId': null, 'programId': null}),
      imageUrl: imageUrl,
    );
    expect(cleared.templateId, isNull);
    expect(cleared.programId, isNull);
  });

  test('deleting the session keeps the program; deleting the program lets go of both', () async {
    final (program, template) = await seedProgram(userId);
    final (workout, _) = await h.db.createWorkout(
      userId: userId,
      body: body({'templateId': template, 'programId': program}),
      imageUrl: imageUrl,
    );

    await h.db.deleteTemplate(coachId: userId, templateId: template);
    final afterSession = await h.db.getWorkout(userId: userId, workoutId: workout.id, imageUrl: imageUrl);
    expect(afterSession.templateId, isNull);
    expect(afterSession.programId, program);

    await h.db.deleteProgram(userId: userId, programId: program);
    final afterProgram = await h.db.getWorkout(userId: userId, workoutId: workout.id, imageUrl: imageUrl);
    expect(afterProgram.programId, isNull);
  });

  test('a superset is stored on a logged exercise and kept by a replace that leaves it out (heart-api#234)', () async {
    final exerciseId = await h.seedGlobalExercise();
    final exerciseRowId = uuidV7();
    WorkoutRequest grouped(Map<String, dynamic> extra) => WorkoutRequest(
      userId: userId,
      body: {
        'name': 'Arms',
        'start': DateTime.utc(2026, 10, 15, 18).toIso8601String(),
        'exercises': [
          {
            'id': exerciseRowId,
            'exercise': exerciseId,
            'order': 0,
            ...extra,
            'sets': [
              {'reps': 10, 'completed': true},
            ],
          },
        ],
      },
    );

    final (workout, _) = await h.db.createWorkout(userId: userId, body: grouped({'superset': 2}), imageUrl: imageUrl);
    expect(workout.single.superset, 2);
    final kept = await h.db.updateWorkout(userId: userId, workoutId: workout.id, body: grouped({}), imageUrl: imageUrl);
    expect(kept.single.superset, 2);
    final read = await h.db.getWorkout(userId: userId, workoutId: workout.id, imageUrl: imageUrl);
    expect(read.single.superset, 2);
  });
}

class _Harness extends DatabaseTestBase;
