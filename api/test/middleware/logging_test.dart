import 'package:heart/middleware/logging.dart';
import 'package:test/test.dart';

void main() {
  group('redactedPath', () {
    test('an invitation token is a secret, so a log keeps none of it', () {
      for (final path in [
        '/invitation-links/s3cret',
        'invitation-links/s3cret',
        '/invitation-links/s3cret/accept',
        '/invitation-links/s3cret/decline',
        '/invitation-links/s3cret/block',
      ]) {
        expect(redactedPath(path), isNot(contains('s3cret')), reason: path);
        expect(redactedPath(path), contains('invitation-links/<token>'), reason: path);
      }
    });

    test('any other path is left as it is', () {
      expect(redactedPath('/workouts/abc'), '/workouts/abc');
      expect(redactedPath('/invitations/abc'), '/invitations/abc');
    });
  });
}
