import 'dart:convert';

import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../helpers/app_harness.dart';

/// Route-level HTTP tests for `routes/events.dart`, the non-HTTP event fan-in.
/// `/events` is a public route, so no auth is involved. The DLQ error path
/// constructs an SQS client inline and is out of scope; covered here are the
/// access gate, an unrecognised payload, and one full dispatch (the exercise
/// asset pipeline callback) that lands back on an injected service.
void main() {
  late AppHarness app;

  setUp(() async => app = await AppHarness.start());
  tearDown(() => app.stop());

  test('forbids a networked request when non-http events are disabled (403)', () async {
    when(app.config.allowNonHttpEvents).thenReturn(false);
    // No x-amzn-request-context header → looks like a direct network call.
    expect((await app.send('POST', '/events', body: {'anything': true})).status, 403);
  });

  test('an unrecognised payload shape is a 500', () async {
    when(app.config.allowNonHttpEvents).thenReturn(true);
    expect((await app.send('POST', '/events', body: {'not': 'an event'})).status, 500);
  });

  test('dispatches an exercise.asset.processed record onto the exercise service (204)', () async {
    when(app.config.allowNonHttpEvents).thenReturn(true);
    when(app.config.cdnAssetUrl(any)).thenReturn('https://cdn.example/asset');
    when(
      app.db.setExerciseMedia(
        key: anyNamed('key'),
        asset: anyNamed('asset'),
        thumbnail: anyNamed('thumbnail'),
      ),
    ).thenAnswer((_) async {});

    final record = jsonEncode({
      'type': 'exercise.asset.processed',
      'key': 'squat',
      'asset': {'key': 'exercises/squat/asset.gif', 'width': 400, 'height': 300},
      'thumbnail': {'key': 'exercises/squat/thumb.gif', 'width': 100, 'height': 75},
    });

    final res = await app.send(
      'POST',
      '/events',
      body: {
        'Records': [
          {'body': record},
        ],
      },
    );
    expect(res.status, 204);
    verify(
      app.db.setExerciseMedia(
        key: 'squat',
        asset: anyNamed('asset'),
        thumbnail: anyNamed('thumbnail'),
      ),
    ).called(1);
  });
}
