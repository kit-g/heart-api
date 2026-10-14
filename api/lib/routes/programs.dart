import 'package:heart/core/handler.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/inputs/inputs.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/models/errors.dart';
import 'package:heart/models/programs.dart';
import 'package:heart_models/heart_models.dart';
import 'package:relic/relic.dart';

Future<ProgramsResponse> getMyPrograms(Request req) async {
  return ProgramsResponse(programs: await req.programService.getPrograms(req.userId));
}

Future<Program> getMyProgram(Request req) {
  return req.programService.getProgram(userId: req.userId, programId: req.rawPathParameters[#programId]!);
}

Future<Model> createProgram(Request req) async {
  final input = await ProgramCreateIn.fromRequest(req);
  final (program, isNew) = await req.programService.createProgramOrExisting(
    userId: req.userId,
    program: input.program,
    sessions: input.sessions,
  );
  if (isNew) return Created(program);
  return program;
}

Future<Program> updateProgram(Request req) {
  return updateProgramById(req, req.rawPathParameters[#programId]!);
}

Future<Program> updateProgramById(Request req, String programId) async {
  final input = await ProgramUpdateIn.fromRequest(req);
  return req.programService.updateProgram(userId: req.userId, programId: programId, program: input.program);
}

Future<Model> deleteProgram(Request req) {
  return deleteProgramById(req, req.rawPathParameters[#programId]!);
}

Future<Model> deleteProgramById(Request req, String programId) async {
  await req.programService.deleteProgram(
    userId: req.userId,
    programId: programId,
    keepTemplates: ProgramDeleteQuery.fromRequest(req).keepTemplates,
  );
  throw const NoContent();
}
