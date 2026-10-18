import 'package:heart/core/handler.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/models/errors.dart';
import 'package:heart/routes/programs.dart';
import 'package:heart_models/heart_models.dart';
import 'package:mockito/mockito.dart';
import 'package:relic_core/relic_core.dart';
import 'package:test/test.dart';

import '../helpers/request.dart';
import '../mocks.mocks.dart';

const _meId = 'u1';
const _programId = '019def00-0000-7000-8000-000000000020';

void main() {
  late MockProgramService service;

  setUp(() {
    service = MockProgramService();
  });

  Request wire(Request req) {
    return req
      ..user = User(id: _meId)
      ..programService = service;
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

    test('a new base is 201', () async {
      when(
        service.createProgramBase(userId: anyNamed('userId'), programId: anyNamed('programId'), base: anyNamed('base')),
      ).thenAnswer((i) async => (i.namedArguments[#base] as ProgramBase, true));

      final result = await createProgramBaseFor(
        wire(
          jsonRequest(
            method: Method.post,
            path: '/',
            body: {'exerciseId': '019def00-0000-7000-8000-000000000001', 'value': 100, 'at': '2026-10-14T18:00:00Z'},
          ),
        ),
        _programId,
      );

      expect(result, isA<Created<ProgramBase>>());
    });
  });
}
