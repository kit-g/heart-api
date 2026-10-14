@Tags(['db'])
library;

import 'package:heart/models/errors.dart';
import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

import 'db_test_utility.dart';

/// Integration coverage of the `SkipService` query strings (heart-api#202).
/// Tagged `db`.
void main() {
  final h = _Harness();

  setUpAll(h.setupDatabase);
  tearDownAll(h.teardownDatabase);

  test('created idempotently with its reason, weather and session', () async {
    final userId = await h.seedProfile();
    final (program, _) = await h.db.createProgramOrExisting(
      userId: userId,
      program: Program(name: 'Getting stronger'),
      sessions: [TemplateRequest(userId: userId, name: 'A')],
    );
    final skip = TrainingSkip(
      id: uuidV7(),
      at: DateTime.utc(2026, 10, 14, 7),
      reason: 'tired',
      weather: Weather(temperature: 4.5, pressure: 1003, pressureTrend: -6),
      templateId: program.sessions.single,
      programId: program.id,
    );

    final (stored, isNew) = await h.db.createSkip(userId: userId, skip: skip);
    final (again, againNew) = await h.db.createSkip(userId: userId, skip: skip);

    expect((isNew, againNew), (true, false));
    expect(again.id, stored.id);
    expect(stored.toMap(), skip.toMap());
  });

  test("someone else's session saves the skip unlinked", () async {
    final userId = await h.seedProfile();
    final stranger = await h.seedProfile();
    final (theirs, _) = await h.db.createProgramOrExisting(
      userId: stranger,
      program: Program(name: 'theirs'),
      sessions: [TemplateRequest(userId: stranger, name: 'A')],
    );

    final (stored, _) = await h.db.createSkip(
      userId: userId,
      skip: TrainingSkip(at: DateTime.utc(2026, 10, 14), templateId: theirs.sessions.single, programId: theirs.id),
    );

    expect(stored.templateId, isNull);
    expect(stored.programId, isNull);
  });

  test("another account's skip id is id_taken", () async {
    final owner = await h.seedProfile();
    final stranger = await h.seedProfile();
    final skip = TrainingSkip(id: uuidV7(), at: DateTime.utc(2026, 10, 14));
    await h.db.createSkip(userId: owner, skip: skip);

    expect(
      () => h.db.createSkip(userId: stranger, skip: skip),
      throwsA(isA<Forbidden>().having((e) => e.code, 'code', 'id_taken')),
    );
  });

  test('listed newest first, a page at a time, and deleted', () async {
    final userId = await h.seedProfile();
    final ids = <String>[];
    for (var day = 1; day <= 3; day++) {
      final (skip, _) = await h.db.createSkip(
        userId: userId,
        skip: TrainingSkip(at: DateTime.utc(2026, 10, day)),
      );
      ids.add(skip.id!);
    }

    final first = await h.db.getSkips(userId: userId, limit: 2);
    expect(first.items.map((s) => s.id), [ids[2], ids[1]]);
    expect(first.hasMore, isTrue);
    final second = await h.db.getSkips(userId: userId, limit: 2, cursor: ids[1]);
    expect(second.items.map((s) => s.id), [ids[0]]);
    expect(second.hasMore, isFalse);

    await h.db.deleteSkip(userId: userId, skipId: ids[0]);
    expect((await h.db.getSkips(userId: userId)).items, hasLength(2));
  });

  test('the account summary counts skips and programs', () async {
    final userId = await h.seedProfile();
    await h.db.createSkip(
      userId: userId,
      skip: TrainingSkip(at: DateTime.utc(2026, 10, 14)),
    );
    await h.db.createProgramOrExisting(
      userId: userId,
      program: Program(name: 'p'),
      sessions: const [],
    );

    final summary = await h.db.getAccountSummary(userId);

    expect(summary[.skips].count, 1);
    expect(summary[.programs].count, 1);
    expect(summary[.programActions].count, 0);
  });
}

class _Harness extends DatabaseTestBase;
