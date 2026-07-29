import 'package:test/test.dart';

import '../helpers/app_harness.dart';

/// Route-level HTTP tests for `routes/feedback.dart`. The screenshot branch
/// publishes to SNS via an inline client and is out of scope for this rig; the
/// message validation and the no-attachment path are covered here.
void main() {
  late AppHarness app;

  setUp(() async => app = await AppHarness.start());
  tearDown(() => app.stop());

  test('rejects a missing message with 400', () async {
    expect((await app.send('POST', '/feedback', body: {})).status, 400);
  });

  test('a message with no screenshot resolves to 204', () async {
    final res = await app.send('POST', '/feedback', body: {'message': 'the app is great'});
    expect(res.status, 204);
    expect(res.body, isEmpty);
  });
}
