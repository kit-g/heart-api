import 'package:heart/models/errors.dart';
import 'package:test/test.dart';

void main() {
  group('NotFound', () {
    test('statusCode is 404', () {
      expect(const NotFound(type: 'Workout', id: 'w1').statusCode, 404);
    });

    test('toMap includes formatted message and default code', () {
      final err = const NotFound(type: 'Workout', id: 'abc');
      expect(err.toMap(), {
        'error': 'not found',
        'code': 'not_found',
        'message': 'Workout #abc not found',
      });
    });

    test('carries a specific code when given one', () {
      final err = const NotFound(type: 'Goal', id: 'g1', code: 'goal_not_found');
      expect(err.code, 'goal_not_found');
      expect(err.toMap()['code'], 'goal_not_found');
    });
  });

  group('BadRequest', () {
    test('statusCode is 400', () {
      expect(const BadRequest(reason: 'bad').statusCode, 400);
    });

    test('toMap exposes reason and defaults code to the category', () {
      expect(const BadRequest(reason: 'missing field').toMap(), {
        'error': 'bad request',
        'code': 'bad_request',
        'reason': 'missing field',
      });
    });

    test('a specific code rides alongside the human reason', () {
      // This is the whole point: a client can branch on `goal_limit` without
      // matching the prose, which is free to change.
      expect(const BadRequest(code: 'goal_limit', reason: 'too many goals').toMap(), {
        'error': 'bad request',
        'code': 'goal_limit',
        'reason': 'too many goals',
      });
    });

    test('toString includes payload when set', () {
      final err = const BadRequest(reason: 'oops', payload: {'k': 'v'});
      expect(err.toString(), contains('oops'));
      expect(err.toString(), contains('{k: v}'));
    });
  });

  group('Forbidden', () {
    test('statusCode is 403', () {
      expect(const Forbidden(reason: 'no').statusCode, 403);
    });

    test('toMap exposes reason', () {
      expect(const Forbidden(reason: 'no').toMap(), {
        'error': 'forbidden',
        'code': 'forbidden',
        'reason': 'no',
      });
    });
  });

  group('NotImplemented', () {
    test('statusCode is 501', () {
      expect(const NotImplemented(reason: 'soon').statusCode, 501);
    });

    test('toMap exposes reason', () {
      expect(const NotImplemented(reason: 'soon').toMap(), {
        'error': 'not implemented',
        'code': 'not_implemented',
        'reason': 'soon',
      });
    });
  });

  group('UnsupportedMediaType', () {
    test('statusCode is 415', () {
      expect(const UnsupportedMediaType(reason: 'json only').statusCode, 415);
    });

    test('toMap exposes reason', () {
      expect(const UnsupportedMediaType(reason: 'json only').toMap(), {
        'error': 'unsupported media type',
        'code': 'unsupported_media_type',
        'reason': 'json only',
      });
    });
  });

  group('NoContent', () {
    test('statusCode is 204', () {
      expect(const NoContent().statusCode, 204);
    });

    test('toMap throws — body is intentionally empty', () {
      expect(() => const NoContent().toMap(), throwsUnimplementedError);
    });
  });
}
