import 'package:heart/models/errors.dart';
import 'package:test/test.dart';

void main() {
  group('NotFound', () {
    test('statusCode is 404', () {
      expect(const NotFound(type: 'Workout', id: 'w1').statusCode, 404);
    });

    test('toMap includes formatted message', () {
      final err = const NotFound(type: 'Workout', id: 'abc');
      expect(err.toMap(), {
        'error': 'not found',
        'message': 'Workout #abc not found',
      });
    });
  });

  group('BadRequest', () {
    test('statusCode is 400', () {
      expect(const BadRequest(reason: 'bad').statusCode, 400);
    });

    test('toMap exposes reason', () {
      expect(const BadRequest(reason: 'missing field').toMap(), {
        'error': 'bad request',
        'reason': 'missing field',
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
        'reason': 'soon',
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
