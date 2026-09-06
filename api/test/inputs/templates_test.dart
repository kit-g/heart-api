import 'package:heart/globals/globals.dart';
import 'package:heart/inputs/inputs.dart';
import 'package:heart/models/errors.dart';
import 'package:heart_models/heart_models.dart';
import 'package:relic_core/relic_core.dart';
import 'package:test/test.dart';

import '../helpers/request.dart';

const _meId = 'u1';
// fixed v7 uuids — the only reference shape the input accepts since the id cutover
const _bench = '0198c1a2-b3c4-7d5e-8f60-718293a4b501';
const _squat = '0198c1a2-b3c4-7d5e-8f60-718293a4b502';
const _rowA = '0198c1a2-b3c4-7d5e-8f60-718293a4b503';
const _rowB = '0198c1a2-b3c4-7d5e-8f60-718293a4b504';
const _pushDay = '0198c1a2-b3c4-7d5e-8f60-718293a4b505';

/// The input layer reads `req.userId`, which the auth middleware normally sets.
Request req({Map<String, dynamic> body = const {}, Map<String, String> query = const {}}) {
  return jsonRequest(body: body, query: query)..user = User(id: _meId);
}

void main() {
  group('TemplateCreateIn', () {
    test('parses a full body onto the SQL params', () async {
      final input = await TemplateCreateIn.fromRequest(
        req(
          body: {
            'name': 'Push day',
            'order': 2,
            'folderId': 'f-1',
            'exercises': [
              {
                'exercise': _bench,
                'order': 0,
                'sets': [
                  {'weight': 60, 'reps': 5},
                ],
              },
            ],
          },
        ),
      );

      expect(input.request.userId, _meId);
      expect(input.request.name, 'Push day');
      expect(input.request.order, 2);
      expect(input.request.folderId, 'f-1');
      expect(input.request.exercises.single.exerciseId, _bench);
      expect(input.request.exercises.single.sets.single.weight, 60);
    });

    test('accepts the full exercise object the app holds, not just a bare id', () async {
      final input = await TemplateCreateIn.fromRequest(
        req(
          body: {
            'exercises': [
              {
                'exercise': {'id': _squat, 'name': 'Squat', 'category': 'Barbell'},
              },
            ],
          },
        ),
      );

      expect(input.request.exercises.single.exerciseId, _squat);
    });

    test('falls back to array position when an exercise omits its order', () async {
      final input = await TemplateCreateIn.fromRequest(
        req(
          body: {
            'exercises': [
              {'exercise': _rowA},
              {'exercise': _rowB},
            ],
          },
        ),
      );

      expect(input.request.exercises.map((e) => e.order), [0, 1]);
    });

    test('an empty template is legal — the user is still building it', () async {
      final input = await TemplateCreateIn.fromRequest(req(body: {'name': 'Draft'}));

      expect(input.request.exercises, isEmpty);
      expect(input.request.order, 0);
    });

    test('a blank name is treated as unnamed rather than rejected', () async {
      final input = await TemplateCreateIn.fromRequest(req(body: {'name': '   '}));
      expect(input.request.name, isNull);
    });

    // The app's WorkoutExercise.toMap() writes `exercise` null-aware off its
    // first set, so an exercise the user emptied in the editor arrives with no
    // `exercise` key at all. Rejecting that would fail the whole save.
    test('drops an exercise the user emptied rather than failing the save', () async {
      final input = await TemplateCreateIn.fromRequest(
        req(
          body: {
            'exercises': [
              {'exercise': _bench, 'order': 0},
              {'id': 'we-2', 'start': '2026-08-02T10:00:00.000Z', 'sets': []},
            ],
          },
        ),
      );

      expect(input.request.exercises.map((e) => e.exerciseId), [_bench]);
    });

    // Previously an exercise with sets but no resolvable reference was silently
    // dropped too — the user saved five exercises and got four back.
    test('rejects an exercise that has sets but no resolvable id', () async {
      await expectLater(
        TemplateCreateIn.fromRequest(
          req(
            body: {
              'exercises': [
                {
                  'order': 0,
                  'sets': [
                    {'reps': 5},
                  ],
                },
              ],
            },
          ),
        ),
        throwsA(isA<BadRequest>()),
      );
    });

    test('rejects an exercise whose nested object has no id', () async {
      await expectLater(
        TemplateCreateIn.fromRequest(
          req(
            body: {
              'exercises': [
                {
                  'exercise': {'name': 'Squat'},
                },
              ],
            },
          ),
        ),
        throwsA(isA<BadRequest>()),
      );
    });

    test('rejects a malformed exercise id before the SQL ever casts it', () async {
      await expectLater(
        TemplateCreateIn.fromRequest(
          req(
            body: {
              'exercises': [
                {'exercise': 'Bench Press'},
              ],
            },
          ),
        ),
        throwsA(isA<BadRequest>()),
      );
    });

    test('rejects a negative rep count', () async {
      await expectLater(
        TemplateCreateIn.fromRequest(
          req(
            body: {
              'exercises': [
                {
                  'exercise': _bench,
                  'sets': [
                    {'reps': -1},
                  ],
                },
              ],
            },
          ),
        ),
        throwsA(isA<BadRequest>()),
      );
    });

    // Assisted movements are logged against bodyweight, and the column has never
    // constrained the sign — the input layer must not start.
    test('accepts a negative weight', () async {
      final input = await TemplateCreateIn.fromRequest(
        req(
          body: {
            'exercises': [
              {
                'exercise': _rowA,
                'sets': [
                  {'weight': -20, 'reps': 8},
                ],
              },
            ],
          },
        ),
      );

      expect(input.request.exercises.single.sets.single.weight, -20);
    });

    // Exactly what the app posts: template.toMap() -> WorkoutExercise.toMap(),
    // which nests the whole exercise object and omits `order` entirely. The
    // template's own `id` is real here (heart-api#66 now validates it as
    // a v7) — Template.id is non-nullable and always the app's local mint, so
    // this is what the wire body actually carries, not a placeholder.
    test('accepts the payload shape the app actually sends', () async {
      final input = await TemplateCreateIn.fromRequest(
        req(
          body: {
            'id': _pushDay,
            'name': 'Push day',
            'order': 0,
            'exercises': [
              {
                'id': 'we-1',
                'exercise': {'id': _bench, 'name': 'Bench Press', 'category': 'Barbell', 'target': 'Chest'},
                'start': '2026-08-02T10:00:00.000Z',
                'sets': [
                  {'id': 's-1', 'completed': false, 'reps': 5, 'weight': 60},
                ],
              },
            ],
          },
        ),
      );

      expect(input.request.id, _pushDay);
      expect(input.request.exercises.single.exerciseId, _bench);
      expect(input.request.exercises.single.order, 0);
      expect(input.request.exercises.single.sets.single.reps, 5);
    });

    test('rejects a malformed top-level id', () async {
      await expectLater(
        TemplateCreateIn.fromRequest(req(body: {'id': 't-1', 'name': 'Push day'})),
        throwsA(isA<BadRequest>()),
      );
    });

    test('rejects exercises that are not an array of objects', () async {
      await expectLater(
        TemplateCreateIn.fromRequest(req(body: {'exercises': 'Bench'})),
        throwsA(isA<BadRequest>()),
      );
      await expectLater(
        TemplateCreateIn.fromRequest(
          req(
            body: {
              'exercises': ['Bench'],
            },
          ),
        ),
        throwsA(isA<BadRequest>()),
      );
    });

    test('rejects a name over the max length', () async {
      await expectLater(
        TemplateCreateIn.fromRequest(req(body: {'name': 'x' * 201})),
        throwsA(isA<BadRequest>()),
      );
    });
  });

  group('TemplateUpdateIn — three-valued filing', () {
    test('no folderId key leaves the filing alone', () async {
      final input = await TemplateUpdateIn.fromRequest(req(body: {'name': 'Renamed'}));

      expect(input.request.movesFolder, isFalse);
      expect(input.request.folderId, isNull);
    });

    test('an explicit null folderId unfiles', () async {
      final input = await TemplateUpdateIn.fromRequest(req(body: {'name': 'X', 'folderId': null}));

      expect(input.request.movesFolder, isTrue);
      expect(input.request.folderId, isNull);
    });

    test('a folderId files it there', () async {
      final input = await TemplateUpdateIn.fromRequest(req(body: {'name': 'X', 'folderId': 'f-2'}));

      expect(input.request.movesFolder, isTrue);
      expect(input.request.folderId, 'f-2');
    });

    test('rejects a non-string folderId', () async {
      await expectLater(
        TemplateUpdateIn.fromRequest(req(body: {'folderId': 42})),
        throwsA(isA<BadRequest>()),
      );
    });
  });

  group('TemplateListQuery', () {
    test('defaults to no filter and no cursor', () {
      final query = TemplateListQuery.fromRequest(req());

      expect(query.cursor, isNull);
      expect(query.folderId, isNull);
      expect(query.unfiledOnly, isFalse);
      expect(query.limit, 30);
    });

    test('folder=none asks for the unfiled ones', () {
      final query = TemplateListQuery.fromRequest(req(query: {'folder': 'none'}));

      expect(query.unfiledOnly, isTrue);
      expect(query.folderId, isNull);
    });

    test('folder=<id> narrows to that folder', () {
      final query = TemplateListQuery.fromRequest(req(query: {'folder': 'f-1'}));

      expect(query.folderId, 'f-1');
      expect(query.unfiledOnly, isFalse);
    });

    test('parses a composite cursor', () {
      final query = TemplateListQuery.fromRequest(req(query: {'cursor': '4:t-2'}));

      expect(query.cursor?.order, 4);
      expect(query.cursor?.id, 't-2');
    });

    test('rejects a cursor that is not a pair', () {
      expect(
        () => TemplateListQuery.fromRequest(req(query: {'cursor': 't-2'})),
        throwsA(isA<BadRequest>()),
      );
    });

    test('clamps the limit', () {
      expect(TemplateListQuery.fromRequest(req(query: {'limit': '999'})).limit, 100);
    });
  });
}
