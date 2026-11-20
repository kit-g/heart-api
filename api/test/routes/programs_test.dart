import 'dart:convert';

import 'package:heart/core/handler.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/models/changes.dart';
import 'package:heart/models/errors.dart';
import 'package:heart/models/programs.dart';
import 'package:heart/routes/programs.dart';
import 'package:heart_models/heart_models.dart';
import 'package:mockito/mockito.dart';
import 'package:relic_core/relic_core.dart';
import 'package:test/test.dart';

import '../helpers/app_harness.dart';
import '../helpers/request.dart';
import '../mocks.mocks.dart';

const _meId = 'u1';
const _programId = '019def00-0000-7000-8000-000000000020';

void main() {
  late MockProgramService service;
  late MockProgramChangeService changes;

  setUp(() {
    service = MockProgramService();
    changes = MockProgramChangeService();
    when(
      changes.writeProgramFields(
        ownerId: anyNamed('ownerId'),
        actorId: anyNamed('actorId'),
        programId: anyNamed('programId'),
        program: anyNamed('program'),
        baseRevision: anyNamed('baseRevision'),
        changeId: anyNamed('changeId'),
      ),
    ).thenAnswer((_) async => null);
  });

  Request wire(Request req) {
    return req
      ..user = User(id: _meId)
      ..programService = service
      ..programChangeService = changes;
  }

  group('createProgram', () {
    test('a new program is 201, created with its sessions for the caller', () async {
      when(
        service.createProgramOrExisting(
          userId: anyNamed('userId'),
          program: anyNamed('program'),
          sessions: anyNamed('sessions'),
        ),
      ).thenAnswer((i) async => (i.namedArguments[#program] as Program, true));

      final result = await createProgram(
        wire(
          jsonRequest(
            method: Method.post,
            path: '/programs',
            body: {
              'name': 'Getting stronger',
              'sessions': [
                {'name': 'A'},
                {'name': 'B'},
              ],
            },
          ),
        ),
      );

      expect(result, isA<Created<Program>>());
      final captured =
          verify(
                service.createProgramOrExisting(
                  userId: _meId,
                  program: anyNamed('program'),
                  sessions: captureAnyNamed('sessions'),
                ),
              ).captured.single
              as List<TemplateRequest>;
      expect(captured.map((s) => s.name), ['A', 'B']);
    });

    test('a session naming a template passes on what joining it needs (heart-api#244)', () async {
      when(
        service.createProgramOrExisting(
          userId: anyNamed('userId'),
          program: anyNamed('program'),
          sessions: anyNamed('sessions'),
        ),
      ).thenAnswer((i) async => (i.namedArguments[#program] as Program, true));
      const templateId = '019def00-0000-7000-8000-000000000021';

      await createProgram(
        wire(
          jsonRequest(
            method: Method.post,
            path: '/programs',
            body: {
              'name': 'From a folder',
              'sessions': [
                {'id': templateId, 'name': 'Push', 'order': 3, 'joined': '2026-10-01T08:00:00.000Z'},
              ],
            },
          ),
        ),
      );

      final captured =
          verify(
                service.createProgramOrExisting(
                  userId: _meId,
                  program: anyNamed('program'),
                  sessions: captureAnyNamed('sessions'),
                ),
              ).captured.single
              as List<TemplateRequest>;
      final session = captured.single;
      expect(session.id, templateId);
      expect(session.order, 3);
      expect(session.joined, DateTime.utc(2026, 10, 1, 8));
    });

    test('a replay is the bare program, 200', () async {
      when(
        service.createProgramOrExisting(
          userId: anyNamed('userId'),
          program: anyNamed('program'),
          sessions: anyNamed('sessions'),
        ),
      ).thenAnswer((i) async => (i.namedArguments[#program] as Program, false));

      final result = await createProgram(
        wire(jsonRequest(method: Method.post, path: '/programs', body: {'name': 'p', 'id': _programId})),
      );

      expect(result, isA<Program>());
    });
  });

  group('the rest', () {
    test('lists the caller\'s programs', () async {
      when(service.getPrograms(_meId)).thenAnswer((_) async => [Program(id: _programId, name: 'p')]);

      final result = await getMyPrograms(wire(jsonRequest(path: '/programs')));

      expect(result.toMap()['programs'], hasLength(1));
    });

    test('a replace goes to the program in the path', () async {
      when(
        service.updateProgram(
          userId: anyNamed('userId'),
          programId: anyNamed('programId'),
          program: anyNamed('program'),
        ),
      ).thenAnswer((i) async => i.namedArguments[#program] as Program);

      final req = wire(jsonRequest(method: Method.put, path: '/programs/$_programId', body: {'name': 'Renamed'}));
      final result = await updateProgramById(req, _programId);

      expect(result.name, 'Renamed');
      verify(service.updateProgram(userId: _meId, programId: _programId, program: anyNamed('program'))).called(1);
    });

    test('delete is 204 and passes keepTemplates on', () async {
      when(
        service.deleteProgram(
          userId: anyNamed('userId'),
          programId: anyNamed('programId'),
          keepTemplates: anyNamed('keepTemplates'),
        ),
      ).thenAnswer((_) async {});

      final req = wire(
        jsonRequest(method: Method.delete, path: '/programs/$_programId', query: {'keepTemplates': 'true'}),
      );

      await expectLater(deleteProgramById(req, _programId), throwsA(isA<NoContent>()));
      verify(service.deleteProgram(userId: _meId, programId: _programId, keepTemplates: true)).called(1);
    });
  });

  group('actions and bases', () {
    test('a new action is 201 for the program in the path; a replay of it is 200', () async {
      var created = true;
      when(
        service.createProgramAction(
          userId: anyNamed('userId'),
          programId: anyNamed('programId'),
          action: anyNamed('action'),
        ),
      ).thenAnswer((i) async => (i.namedArguments[#action] as ProgramAction, created));
      Request body() => wire(
        jsonRequest(method: Method.post, path: '/', body: {'kind': 'pause', 'at': '2026-10-14T18:00:00Z'}),
      );

      expect(await createProgramActionFor(body(), _programId), isA<Created<ProgramAction>>());
      created = false;
      expect(await createProgramActionFor(body(), _programId), isA<ProgramAction>());
      verify(
        service.createProgramAction(userId: _meId, programId: _programId, action: anyNamed('action')),
      ).called(2);
    });
  });

  test('a replace on a coach\'s copy goes through the history instead', () async {
    final copy = Program(id: _programId, name: 'Recorded');
    when(
      changes.writeProgramFields(
        ownerId: anyNamed('ownerId'),
        actorId: anyNamed('actorId'),
        programId: anyNamed('programId'),
        program: anyNamed('program'),
        baseRevision: 3,
        changeId: anyNamed('changeId'),
      ),
    ).thenAnswer((_) async => copy);
    when(changes.otherSideOf(actorId: anyNamed('actorId'), programId: anyNamed('programId')))
        .thenAnswer((_) async => null);

    final req = wire(
      jsonRequest(method: Method.put, path: '/programs/$_programId', body: {'name': 'X', 'baseRevision': 3}),
    );
    expect((await updateProgramById(req, _programId)).name, 'Recorded');
    verifyNever(
      service.updateProgram(userId: anyNamed('userId'), programId: anyNamed('programId'), program: anyNamed('program')),
    );
  });

  group('through the real app', () {
    late AppHarness app;

    setUp(() async => app = await AppHarness.start());
    tearDown(() => app.stop());

    const action = '019def00-0000-7000-8000-000000000030';
    const base = '019def00-0000-7000-8000-000000000031';
    const exercise = '019def00-0000-7000-8000-000000000001';

    test('reads the caller\'s own program', () async {
      when(
        app.db.getProgram(userId: anyNamed('userId'), programId: anyNamed('programId')),
      ).thenAnswer((_) async => Program(id: _programId, name: 'Mine'));

      final res = await app.send('GET', '/programs/$_programId');

      expect(res.status, 200);
      expect(Program.fromJson(jsonDecode(res.body) as Map).name, 'Mine');
      verify(app.db.getProgram(userId: _meId, programId: _programId)).called(1);
    });

    test('a new action goes on the program in the path, 201', () async {
      when(
        app.db.createProgramAction(
          userId: anyNamed('userId'),
          programId: anyNamed('programId'),
          action: anyNamed('action'),
        ),
      ).thenAnswer((i) async => (i.namedArguments[#action] as ProgramAction, true));

      final res = await app.send(
        'POST',
        '/programs/$_programId/actions',
        body: {'id': action, 'kind': 'pause', 'at': '2026-10-14T18:00:00Z'},
      );

      expect(res.status, 201);
      verify(app.db.createProgramAction(userId: _meId, programId: _programId, action: anyNamed('action'))).called(1);
    });

    test('undoing an action names the program and the action, 204', () async {
      when(
        app.db.deleteProgramAction(
          userId: anyNamed('userId'),
          programId: anyNamed('programId'),
          actionId: anyNamed('actionId'),
        ),
      ).thenAnswer((_) async {});

      final res = await app.send('DELETE', '/programs/$_programId/actions/$action');

      expect(res.status, 204);
      verify(app.db.deleteProgramAction(userId: _meId, programId: _programId, actionId: action)).called(1);
    });

    test('lists the program\'s bases', () async {
      when(app.db.getProgramBases(userId: anyNamed('userId'), programId: anyNamed('programId'))).thenAnswer(
        (_) async => [ProgramBase(id: base, exerciseId: exercise, value: 100, at: DateTime.utc(2026, 10))],
      );

      final res = await app.send('GET', '/programs/$_programId/bases');

      expect(res.status, 200);
      expect(((jsonDecode(res.body) as Map)['bases'] as List).single, containsPair('id', base));
      verify(app.db.getProgramBases(userId: _meId, programId: _programId)).called(1);
    });

    test('every program\'s history in one read, from the cursor the app passes (heart-api#458)', () async {
      const since = ChangeCursor(xid: '42', id: _programId);
      when(app.db.getProgramHistoryChanges(userId: anyNamed('userId'), since: anyNamed('since'))).thenAnswer(
        (_) async => ProgramHistoryChanges(
          programs: [
            (
              programId: _programId,
              actions: [ProgramAction(id: _programId, kind: .pause, at: DateTime.utc(2026, 10))],
              bases: const [],
            ),
          ],
          cursor: const ChangeCursor(xid: '43', id: _programId),
          hasMore: false,
        ),
      );

      final res = await app.send('GET', '/programs/history?since=$since');

      expect(res.status, 200);
      final body = jsonDecode(res.body) as Map;
      final program = (body['programs'] as List).single as Map;
      expect(program['programId'], _programId);
      expect((program['actions'] as List).single, containsPair('kind', 'pause'));
      expect(program['bases'], isEmpty);
      expect(body['cursor'], const ChangeCursor(xid: '43', id: _programId).toString());
      expect(body['hasMore'], isFalse);
      final read =
          verify(
                app.db.getProgramHistoryChanges(userId: _meId, since: captureAnyNamed('since')),
              ).captured.single
              as ChangeCursor;
      expect((read.xid, read.id), ('42', _programId));
    });

    test('a since that is no cursor is a 400, never a fresh start', () async {
      final res = await app.send('GET', '/programs/history?since=nope');
      expect(res.status, 400);
      verifyNever(app.db.getProgramHistoryChanges(userId: anyNamed('userId'), since: anyNamed('since')));
    });

    test('a new base is the caller\'s own, 201', () async {
      when(
        app.db.createProgramBase(
          userId: anyNamed('userId'),
          programId: anyNamed('programId'),
          base: anyNamed('base'),
        ),
      ).thenAnswer((i) async => (i.namedArguments[#base] as ProgramBase, true));

      final res = await app.send(
        'POST',
        '/programs/$_programId/bases',
        body: {'exerciseId': exercise, 'value': 100, 'at': '2026-10-14T18:00:00Z'},
      );

      expect(res.status, 201);
      verify(
        app.db.createProgramBase(userId: _meId, programId: _programId, base: anyNamed('base')),
      ).called(1);
    });

    test('deleting a base names the program and the base, 204', () async {
      when(
        app.db.deleteProgramBase(
          userId: anyNamed('userId'),
          programId: anyNamed('programId'),
          baseId: anyNamed('baseId'),
        ),
      ).thenAnswer((_) async {});

      final res = await app.send('DELETE', '/programs/$_programId/bases/$base');

      expect(res.status, 204);
      verify(app.db.deleteProgramBase(userId: _meId, programId: _programId, baseId: base)).called(1);
    });
  });
}
