import 'dart:convert';

import 'package:heart/globals/globals.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/middleware/s3.dart';
import 'package:heart/models/errors.dart';
import 'package:heart/routes/workouts.dart';
import 'package:heart_models/heart_models.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../helpers/request.dart';
import '../mocks.mocks.dart';

void main() {
  const header =
      'title,start_time,end_time,description,exercise_title,superset_id,exercise_notes,'
      'set_index,set_type,weight_kg,reps,distance_km,duration_seconds,rpe';
  // This date is deliberately unreadable: the fallback must not retain a
  // health-bearing file just because the workout parser cannot read its rows.
  const row = 'Workout,unknown,unknown,,Bench Press,,,0,normal,50,8,,,';

  for (final envelope in [false, true]) {
    for (final dryRun in [false, true]) {
      for (final column in ['heartRate', 'Heart-Rate', 'HRV', 'sleep_minutes', 'body_mass', 'steps']) {
        test('rejects $column before any import side effect (JSON: $envelope, preview: $dryRun)', () async {
          final storage = MockImportStorage();
          final workouts = MockApiWorkoutService();
          final csv = '$header,"$column"\r\n$row,72\r\n';
          final query = {'source': 'hevy', 'dryRun': '$dryRun'};
          final request =
              switch (envelope) {
                  true => jsonRequest(path: '/workouts/imports', query: query, body: {'csv': csv}),
                  false => textRequest(path: '/workouts/imports', query: query, body: csv),
                }
                ..user = User(id: 'u1')
                ..importStorage = storage
                ..workoutsService = workouts;

          await expectLater(
            importWorkouts(request),
            throwsA(isA<BadRequest>().having((e) => e.code, 'code', 'health_data')),
          );
          verifyZeroInteractions(storage);
          verifyZeroInteractions(workouts);
        });
      }
    }
  }

  test('BOM, sep hint and a quoted multiline header cannot hide health fields', () async {
    final csv = '\ufeffsep=;\r\n${header.replaceAll(',', ';')};"Heart\nRate"\r\n${row.replaceAll(',', ';')};72\r\n';
    final request = textRequest(query: {'source': 'hevy'}, body: csv);
    await expectLater(
      importWorkouts(request),
      throwsA(isA<BadRequest>().having((e) => e.code, 'code', 'health_data')),
    );
  });

  test('JSON parsing still rejects nested health fields outside the CSV string', () async {
    final request = jsonRequest(
      query: {'source': 'hevy'},
      body: {'csv': '$header\n$row', 'extra': jsonDecode('{"heartRate":72}')},
    );
    await expectLater(
      importWorkouts(request),
      throwsA(isA<BadRequest>().having((e) => e.code, 'code', 'health_data')),
    );
  });
}
