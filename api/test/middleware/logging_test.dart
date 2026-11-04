import 'package:heart/core/response.dart';
import 'package:heart/middleware/logging.dart';
import 'package:logging/logging.dart';
import 'package:relic/relic.dart' hide Logger;
import 'package:test/test.dart';

import '../helpers/request.dart';

/// The line [requestLogging] writes for a request to [path].
Future<String> _logged(String path) async {
  final lines = <String>[];
  final subscription = Logger('Request').onRecord.listen((record) => lines.add(record.message));
  try {
    await requestLogging()((_) => JsonResponse.ok())(bareRequest(method: Method.get, path: path));
  } finally {
    await subscription.cancel();
  }
  return lines.single;
}

void main() {
  group('requestLogging', () {
    test('an invitation token is a secret, so a log keeps none of it', () async {
      for (final path in [
        '/invitation-links/s3cret',
        '//invitation-links/s3cret',
        '/invitation-links/s3cret/accept',
        '/invitation-links/s3cret/decline',
        '/invitation-links/s3cret/block',
      ]) {
        final line = await _logged(path);
        expect(line, isNot(contains('s3cret')), reason: path);
        expect(line, contains('invitation-links/<token>'), reason: path);
      }
    });

    test('any other path is left as it is', () async {
      expect(await _logged('/workouts/abc'), contains('/workouts/abc'));
      expect(await _logged('/invitations/abc'), contains('/invitations/abc'));
    });
  });
}
