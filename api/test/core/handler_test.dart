import 'package:heart/core/handler.dart';
import 'package:heart/core/response.dart';
import 'package:heart/models/errors.dart';
import 'package:heart_models/heart_models.dart';
import 'package:relic_core/relic_core.dart';
import 'package:test/test.dart';

import '../helpers/request.dart';

class _Ok implements Model {
  @override
  Map<String, dynamic> toMap() => {'ok': true};
}

/// Locks the status-code contract of the single choke point every route flows
/// through (`apiHandler`): a returned model → 200, and each thrown type mapped
/// to the right status.
void main() {
  Future<int> status(ModelHandler handler) async {
    final result = await apiHandler(handler)(bareRequest());
    return (result as Response).statusCode;
  }

  test('a returned model becomes 200', () async {
    expect(await status((_) async => _Ok()), 200);
  });

  test('a null return becomes 200 with an empty body', () async {
    expect(await status((_) async => null), 200);
  });

  test('NoContent becomes 204', () async {
    expect(await status((_) async => throw const NoContent()), 204);
  });

  test('BadRequest becomes 400', () async {
    expect(await status((_) async => throw const BadRequest(reason: 'bad')), 400);
  });

  test('Forbidden becomes 403', () async {
    expect(await status((_) async => throw const Forbidden(reason: 'no')), 403);
  });

  test('NotFound becomes 404', () async {
    expect(await status((_) async => throw const NotFound(type: 'Workout', id: 'w-1')), 404);
  });

  test('a TypeError (sloppy client input) becomes 400', () async {
    expect(
      await status((_) async {
        // A number where a string was expected, slipping past validation.
        (<String, dynamic>{'n': 1}['n'] as String).length;
        return _Ok();
      }),
      400,
    );
  });

  test('a FormatException becomes 400', () async {
    expect(await status((_) async => throw const FormatException('nope')), 400);
  });

  test('UnsupportedMediaType becomes 415', () async {
    expect(await status((_) async => throw const UnsupportedMediaType(reason: 'json only')), 415);
  });

  test('UnimplementedError becomes 501', () async {
    expect(await status((_) async => throw UnimplementedError('later')), 501);
  });

  test('an unexpected error becomes 500', () async {
    expect(await status((_) async => throw StateError('boom')), 500);
  });
}
