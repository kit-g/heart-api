import 'dart:convert';

import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:heart/models/errors.dart';

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

  /// The endpoint's contract with SQS, both directions.
  ///
  /// `204` meaning "processed" was always true and always tested. The converse
  /// was neither: a non-2xx is still a normal Lambda result, so the adapter
  /// reported success and the message was deleted — a permanent failure left no
  /// retry and no DLQ entry. Only an exception escaping the handler fails the
  /// invocation, so that is what these two pin down.
  group('SQS outcome semantics', () {
    String assetRecord() => jsonEncode({
      'type': 'exercise.asset.processed',
      'key': 'squat',
      'asset': {'key': 'exercises/squat/asset.gif', 'width': 200, 'height': 150},
      'thumbnail': {'key': 'exercises/squat/thumb.gif', 'width': 100, 'height': 75},
    });

    Future<({int status, String body})> sendAsset() => app.send(
      'POST',
      '/events',
      body: {
        'Records': [
          {'body': assetRecord()},
        ],
      },
    );

    setUp(() {
      when(app.config.allowNonHttpEvents).thenReturn(true);
      when(app.config.cdnAssetUrl(any)).thenReturn('https://cdn.example/asset');
    });

    test('a transient failure escapes the handler, so the invocation fails and SQS can redeliver', () async {
      when(
        app.db.setExerciseMedia(key: anyNamed('key'), asset: anyNamed('asset'), thumbnail: anyNamed('thumbnail')),
      ).thenThrow(StateError('connection pool exhausted'));

      // Not a 204: the handler must not report this message as processed.
      expect((await sendAsset()).status, isNot(204));
    });

    test('a permanent 4xx is absorbed, because redelivering it cannot change the outcome', () async {
      when(
        app.db.setExerciseMedia(key: anyNamed('key'), asset: anyNamed('asset'), thumbnail: anyNamed('thumbnail')),
      ).thenThrow(const NotFound(type: 'Exercise', id: 'squat'));

      // 204, so the message is consumed rather than retried three times for
      // nothing. The DLQ write is what records it; that path builds its own SQS
      // client and is out of scope here, as noted above.
      expect((await sendAsset()).status, 204);
    });
  });
}
