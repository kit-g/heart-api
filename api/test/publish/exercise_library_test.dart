import 'dart:convert';

import 'package:heart/publish/exercise_library.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../mocks.mocks.dart';

/// Unit coverage for the CDN generator's pure rendering: given a fake
/// `ExerciseService`, does it produce the right bytes? No database, no I/O —
/// those are exercised separately by the `db`-tagged integration test and by
/// hand against the seeded local Postgres.
void main() {
  late MockExerciseService service;

  setUp(() => service = MockExerciseService());

  test('each locale file is exactly jsonEncode of the service response for that locale', () async {
    when(service.getExercises(anonymousUserId, locale: 'en')).thenAnswer(
      (_) async => {
        'exercises': [
          {'id': '1', 'key': 'squat', 'name': 'Squat'},
        ],
      },
    );
    when(service.getExercises(anonymousUserId, locale: 'fr')).thenAnswer(
      (_) async => {
        'exercises': [
          {'id': '1', 'key': 'squat', 'name': 'Le Squat'},
        ],
      },
    );

    final publication = await renderLibraryPublication(
      service: service,
      locales: const ['en', 'fr'],
      version: 'deadbeef',
      generatedAt: DateTime.utc(2026, 1, 1),
    );

    expect(
      publication.localeFiles['en'],
      jsonEncode({
        'exercises': [
          {'id': '1', 'key': 'squat', 'name': 'Squat'},
        ],
      }),
    );
    expect(
      publication.localeFiles['fr'],
      jsonEncode({
        'exercises': [
          {'id': '1', 'key': 'squat', 'name': 'Le Squat'},
        ],
      }),
    );
  });

  test('the manifest lists exactly the requested locales, with version and generated_at', () async {
    when(service.getExercises(any, locale: anyNamed('locale'))).thenAnswer((_) async => {'exercises': []});

    final publication = await renderLibraryPublication(
      service: service,
      locales: const ['en', 'es', 'es_ES'],
      version: 'deadbeef',
      generatedAt: DateTime.utc(2026, 1, 1, 12),
    );

    expect(
      jsonDecode(publication.manifest),
      {
        'version': 'deadbeef',
        'generated_at': '2026-01-01T12:00:00.000Z',
        'locales': ['en', 'es', 'es_ES'],
      },
    );
  });

  test('every locale is fetched under the anonymous sentinel, never a real user id', () async {
    when(service.getExercises(any, locale: anyNamed('locale'))).thenAnswer((_) async => {'exercises': []});

    await renderLibraryPublication(
      service: service,
      locales: const ['en'],
      version: 'deadbeef',
      generatedAt: DateTime.utc(2026),
    );

    verify(service.getExercises(anonymousUserId, locale: 'en')).called(1);
  });

  test('rejects a locale set without "en", the fallback base for everything else', () async {
    expect(
      () => renderLibraryPublication(
        service: service,
        locales: const ['es', 'es_ES'],
        version: 'deadbeef',
        generatedAt: DateTime.utc(2026),
      ),
      throwsArgumentError,
    );
    verifyZeroInteractions(service);
  });
}
