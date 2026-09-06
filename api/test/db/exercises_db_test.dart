@Tags(['db'])
library;

import 'package:heart/models/errors.dart';
import 'package:test/test.dart';

import 'db_test_utility.dart';

/// Full integration coverage of the `ExerciseService` query strings against a
/// live Postgres: list (globals + owned, owned-only filter, locale translations,
/// per-user preferences), create, owner-scoped update, and set-media-by-name,
/// plus the user-scoping / NotFound branches the SQL encodes.
///
/// Tagged `db` — skipped by the default `dart test`. Run with:
///   dart test --run-skipped -t db
void main() {
  final h = _Harness();

  late String ownerId;
  late String otherId; // a second, unrelated user

  /// Finds the exercise with [id] in a `getExercises` response list, or null.
  Map<String, dynamic>? findEx(List<dynamic> list, String id) {
    for (final e in list) {
      final m = e as Map<String, dynamic>;
      if (m['id'] == id) return m;
    }
    return null;
  }

  setUpAll(() async {
    await h.setupDatabase();
    ownerId = await h.seedProfile();
    otherId = await h.seedProfile();
  });

  tearDownAll(h.teardownDatabase);

  group('getExercises', () {
    test('returns both global and user-owned exercises, flagged by ownership', () async {
      final globalId = await h.seedGlobalExercise();
      final owned = await h.db.createExercise(
        userId: ownerId,
        name: h.uniqueName('Owned'),
        category: 'Dumbbell',
        target: 'Biceps',
      );
      final ownedId = owned['id'].toString();

      final res = await h.db.getExercises(ownerId);
      final list = res['exercises'] as List;

      final g = findEx(list, globalId);
      final o = findEx(list, ownedId);
      expect(g, isNotNull);
      expect(o, isNotNull);
      expect(g!['own'], isFalse); // user_id IS NULL → not owned
      expect(o!['own'], isTrue); // user_id = caller → owned
    });

    test('owned filter returns only the caller\'s exercises, excluding globals', () async {
      // Isolated owner so the owned-only result contains nothing but this test's rows.
      final soloId = await h.seedProfile();
      final globalId = await h.seedGlobalExercise();
      final mine = await h.db.createExercise(
        userId: soloId,
        name: h.uniqueName('Mine'),
        category: 'Barbell',
        target: 'Back',
      );
      final mineId = mine['id'].toString();

      final res = await h.db.getExercises(soloId, owned: true);
      final list = res['exercises'] as List;

      expect(findEx(list, mineId), isNotNull);
      expect(findEx(list, globalId), isNull); // globals filtered out
      expect(list.every((e) => (e as Map)['own'] == true), isTrue);
    });

    test('applies locale translations to name and instructions when present', () async {
      final id = await h.seedGlobalExercise();
      await h.exec(
        'INSERT INTO exercise_translations (exercise_id, locale, name, instructions) '
        'VALUES (@id::uuid, @loc, @n, @i)',
        {'id': id, 'loc': 'es', 'n': 'Sentadilla', 'i': 'Instrucciones en espanol'},
      );

      final translated = findEx((await h.db.getExercises(ownerId, locale: 'es'))['exercises'] as List, id);
      expect(translated!['name'], 'Sentadilla');
      expect(translated['instructions'], 'Instrucciones en espanol');

      // A locale with no translation row falls back to the base columns.
      final base = findEx((await h.db.getExercises(ownerId, locale: 'de'))['exercises'] as List, id);
      expect(base!['name'], isNot('Sentadilla'));
    });

    test('a regional locale chains through its base language before the master columns', () async {
      final id = await h.seedGlobalExercise();
      await h.exec(
        'INSERT INTO exercise_translations (exercise_id, locale, name, instructions, validated) '
        'VALUES (@id::uuid, @loc, @n, @i, false)',
        {'id': id, 'loc': 'es', 'n': 'Sentadilla', 'i': 'Instrucciones neutras'},
      );

      // no es_ES row → the es copy serves, flag included (es_ES -> es -> en)
      final regional = findEx((await h.db.getExercises(ownerId, locale: 'es_ES'))['exercises'] as List, id);
      expect(regional!['name'], 'Sentadilla');
      expect(regional['instructions'], 'Instrucciones neutras');
      expect(regional['validated'], isFalse);

      // a concrete es_ES row wins over the base language, per field
      await h.exec(
        'INSERT INTO exercise_translations (exercise_id, locale, name, validated) '
        'VALUES (@id::uuid, @loc, @n, true)',
        {'id': id, 'loc': 'es_ES', 'n': 'Sentadilla castellana'},
      );
      final castilian = findEx((await h.db.getExercises(ownerId, locale: 'es_ES'))['exercises'] as List, id);
      expect(castilian!['name'], 'Sentadilla castellana');
      // missing fields still read from the base language, not the master
      expect(castilian['instructions'], 'Instrucciones neutras');
      expect(castilian['validated'], isTrue);
    });

    test('ships copy provenance: validated follows whichever copy the locale serves', () async {
      final id = await h.seedGlobalExercise();
      await h.exec('UPDATE exercises SET validated = false WHERE id = @id::uuid', {'id': id});
      await h.exec(
        'INSERT INTO exercise_translations (exercise_id, locale, name, instructions, validated) '
        'VALUES (@id::uuid, @loc, @n, @i, true)',
        {'id': id, 'loc': 'fr', 'n': 'Nom relu', 'i': 'Relu par un humain'},
      );

      // fallback copy → the exercises row's flag
      final base = findEx((await h.db.getExercises(ownerId))['exercises'] as List, id);
      expect(base!['validated'], isFalse);

      // translated copy → the translation row's own flag, not the fallback's
      final fr = findEx((await h.db.getExercises(ownerId, locale: 'fr'))['exercises'] as List, id);
      expect(fr!['validated'], isTrue);
    });

    test('a user-created exercise takes no stance: validated is null', () async {
      final own = await h.db.createExercise(
        userId: ownerId,
        name: h.uniqueName('My Move'),
        category: 'Dumbbell',
        target: 'Arms',
      );
      final row = findEx((await h.db.getExercises(ownerId))['exercises'] as List, own['id'].toString());
      expect(row, isNotNull);
      expect(row!['validated'], isNull);
    });

    test('surfaces the caller\'s per-exercise unit and rest-timer preferences', () async {
      final id = await h.seedGlobalExercise();
      await h.exec(
        'INSERT INTO exercise_preferences (user_id, exercise_id, unit_system, rest_timer) '
        'VALUES (@u, @e::uuid, @us, @rt)',
        {'u': ownerId, 'e': id, 'us': 'metric', 'rt': 90},
      );

      final mine = findEx((await h.db.getExercises(ownerId))['exercises'] as List, id);
      expect(mine!['unit_system'], 'metric');
      expect(mine['rest_timer'], 90);

      // Another user, who has no preference row, sees nulls (LEFT JOIN miss).
      final theirs = findEx((await h.db.getExercises(otherId))['exercises'] as List, id);
      expect(theirs!['unit_system'], isNull);
      expect(theirs['rest_timer'], isNull);
    });
  });

  group('movement', () {
    /// The blob exactly as scripts/library_locales.py writes it — camelCase, so
    /// storage and wire are the same shape and reads ship it verbatim.
    const stored =
        '{"groups": ["squat_bilateral"], "axialLoad": "high", '
        '"stability": "free", "unilateral": false, "impact": "none", "skill": "moderate"}';

    Future<void> setMovement(String exerciseId) => h.exec(
      'UPDATE exercises SET movement = @m::jsonb WHERE id = @id::uuid',
      {'m': stored, 'id': exerciseId},
    );

    test('getExercises ships the blob through in its wire form', () async {
      final id = await h.seedGlobalExercise();
      await setMovement(id);

      final row = findEx((await h.db.getExercises(ownerId))['exercises'] as List, id);
      final movement = row!['movement'] as Map<String, dynamic>;

      expect(movement['groups'], ['squat_bilateral']);
      expect(movement['axialLoad'], 'high');
      expect(movement['stability'], 'free');
      expect(movement['unilateral'], isFalse);
      expect(movement['impact'], 'none');
      expect(movement['skill'], 'moderate');

      // Movement.fromJson reads camelCase only, so a snake_cased key reaching
      // the client would read as axialLoad = none and offer the lifter exactly
      // the high-compression exercise they filtered out.
      expect(movement.containsKey('axial_load'), isFalse);
    });

    test('getExercises returns null for an exercise with no substitutes', () async {
      final id = await h.seedGlobalExercise();
      final row = findEx((await h.db.getExercises(ownerId))['exercises'] as List, id);
      expect(row!['movement'], isNull);
    });

    test('createExercise returns a null movement for a user-made exercise', () async {
      final row = await h.db.createExercise(
        userId: ownerId,
        name: h.uniqueName('NoMovement'),
        category: 'Barbell',
        target: 'Chest',
      );
      expect(row.containsKey('movement'), isTrue);
      expect(row['movement'], isNull);
    });

    test('updateExercise returns the movement rather than dropping it', () async {
      final created = await h.db.createExercise(
        userId: ownerId,
        name: h.uniqueName('KeepsMovement'),
        category: 'Barbell',
        target: 'Legs',
      );
      final id = created['id'].toString();
      await setMovement(id);

      // A patch unrelated to movement must still round-trip it, or the client
      // would overwrite its cached copy with an empty Movement.
      final updated = await h.db.updateExercise(userId: ownerId, exerciseId: id, target: 'Back');
      expect(updated['target'], 'Back');
      expect((updated['movement'] as Map)['axialLoad'], 'high');
    });
  });

  group('health', () {
    /// The blob exactly as scripts/library_locales.py writes it — the activity
    /// camelCased, so storage and wire are the same shape.
    const stored = '{"activity": "cyclingIndoor"}';

    Future<void> setHealth(String exerciseId) => h.exec(
      'UPDATE exercises SET health = @h::jsonb WHERE id = @id::uuid',
      {'h': stored, 'id': exerciseId},
    );

    test('getExercises ships the blob through in its wire form', () async {
      final id = await h.seedGlobalExercise();
      await setHealth(id);

      final row = findEx((await h.db.getExercises(ownerId))['exercises'] as List, id);
      final health = row!['health'] as Map<String, dynamic>;

      // HealthActivity.fromString reads camelCase only and throws otherwise,
      // so a snake_cased value reaching the client is a failed library read,
      // not a workout quietly written to the health store as strength.
      expect(health['activity'], 'cyclingIndoor');
    });

    test('getExercises returns null for an unannotated exercise', () async {
      final id = await h.seedGlobalExercise();
      final row = findEx((await h.db.getExercises(ownerId))['exercises'] as List, id);
      expect(row!.containsKey('health'), isTrue);
      expect(row['health'], isNull); // the client derives from category
    });

    test('createExercise returns a null health for a user-made exercise', () async {
      final row = await h.db.createExercise(
        userId: ownerId,
        name: h.uniqueName('NoHealth'),
        category: 'Cardio',
        target: 'Cardio',
      );
      expect(row.containsKey('health'), isTrue);
      expect(row['health'], isNull);
    });

    test('updateExercise returns the health rather than dropping it', () async {
      final created = await h.db.createExercise(
        userId: ownerId,
        name: h.uniqueName('KeepsHealth'),
        category: 'Cardio',
        target: 'Cardio',
      );
      final id = created['id'].toString();
      await setHealth(id);

      final updated = await h.db.updateExercise(userId: ownerId, exerciseId: id, target: 'Legs');
      expect(updated['target'], 'Legs');
      expect((updated['health'] as Map)['activity'], 'cyclingIndoor');
    });
  });

  group('createExercise', () {
    test('persists a user-owned exercise and returns it flagged own', () async {
      final name = h.uniqueName('Create');
      final row = await h.db.createExercise(
        userId: ownerId,
        name: name,
        category: 'Machine',
        target: 'Legs',
        instructions: 'Push through the heels',
      );

      expect(row['name'], name);
      expect(row['category'], 'Machine');
      expect(row['target'], 'Legs');
      expect(row['instructions'], 'Push through the heels');
      expect(row['own'], isTrue);
      expect(row['archived'], isFalse); // column default
    });

    test('name uniqueness is per-user, so two users may reuse the same name', () async {
      final name = h.uniqueName('Shared');
      final a = await h.db.createExercise(userId: ownerId, name: name, category: 'Barbell', target: 'Chest');
      final b = await h.db.createExercise(userId: otherId, name: name, category: 'Barbell', target: 'Chest');
      expect(a['id'], isNot(b['id']));
    });

    // kit-g/heart-api#66: anonymous-account upsync replay. The client mints its
    // own id offline and may retry a create (flaky network, app relaunch)
    // without knowing whether the first POST landed; these cover the replay
    // being a safe no-op instead of a duplicate or an error.
    test('reposting the same client id is idempotent: first creates, second is a no-op', () async {
      const id = '019def00-0000-7000-8000-0000000000e1';
      final name = h.uniqueName('Idempotent');

      final first = await h.db.createExercise(
        userId: ownerId,
        id: id,
        name: name,
        category: 'Barbell',
        target: 'Chest',
      );
      expect(first['created'], isTrue);
      expect(first['id'], id);

      // Same id, different payload — the replay is ignored wholesale, not
      // merged; the original row comes back untouched.
      final second = await h.db.createExercise(
        userId: ownerId,
        id: id,
        name: h.uniqueName('ShouldBeIgnored'),
        category: 'Dumbbell',
        target: 'Legs',
      );
      expect(second['created'], isFalse);
      expect(second['id'], id);
      expect(second['name'], name);
      expect(second['category'], 'Barbell');

      final mine = (await h.db.getExercises(ownerId, owned: true))['exercises'] as List;
      expect(mine.where((e) => (e as Map)['id'] == id), hasLength(1));
    });

    test('a new id colliding on name (case-insensitive) resolves to the pre-existing row', () async {
      final name = h.uniqueName('CaseName');
      final original = await h.db.createExercise(userId: ownerId, name: name, category: 'Barbell', target: 'Chest');
      final originalId = original['id'].toString();

      const newId = '019def00-0000-7000-8000-0000000000e2';
      final result = await h.db.createExercise(
        userId: ownerId,
        id: newId,
        name: name.toUpperCase(),
        category: 'Machine',
        target: 'Back',
      );

      expect(result['created'], isFalse);
      expect(result['id'], originalId); // the pre-existing custom's id, not newId
      expect(result['category'], 'Barbell'); // untouched by the colliding call's payload

      final mine = (await h.db.getExercises(ownerId, owned: true))['exercises'] as List;
      expect(mine.where((e) => (e as Map)['id'] == newId), isEmpty); // newId was never inserted
    });

    test('an id already owned by a different user is Forbidden with id_taken', () async {
      const id = '019def00-0000-7000-8000-0000000000e3';
      await h.db.createExercise(
        userId: otherId,
        id: id,
        name: h.uniqueName('TakenById'),
        category: 'Barbell',
        target: 'Chest',
      );

      await expectLater(
        h.db.createExercise(
          userId: ownerId,
          id: id,
          name: h.uniqueName('AttemptedTake'),
          category: 'Barbell',
          target: 'Chest',
        ),
        throwsA(isA<Forbidden>().having((e) => e.code, 'code', 'id_taken')),
      );
    });
  });

  group('updateExercise', () {
    test('the owner updates only the provided fields (coalesce preserves the rest)', () async {
      final created = await h.db.createExercise(
        userId: ownerId,
        name: h.uniqueName('Upd'),
        category: 'Barbell',
        target: 'Chest',
        instructions: 'original',
      );
      final id = created['id'].toString();

      // Patch category only; target/instructions/archived must be preserved.
      final updated = await h.db.updateExercise(userId: ownerId, exerciseId: id, category: 'Dumbbell');
      expect(updated['category'], 'Dumbbell');
      expect(updated['target'], 'Chest'); // unchanged
      expect(updated['instructions'], 'original'); // unchanged
      expect(updated['archived'], isFalse);

      final archived = await h.db.updateExercise(userId: ownerId, exerciseId: id, archived: true);
      expect(archived['archived'], isTrue);
    });

    test('updating another user\'s exercise throws NotFound', () async {
      final created = await h.db.createExercise(
        userId: ownerId,
        name: h.uniqueName('Guarded'),
        category: 'Barbell',
        target: 'Chest',
      );
      await expectLater(
        h.db.updateExercise(userId: otherId, exerciseId: created['id'].toString(), category: 'x'),
        throwsA(isA<NotFound>()),
      );
    });

    test('a global exercise cannot be updated by any user (NotFound)', () async {
      final id = await h.seedGlobalExercise();
      await expectLater(
        h.db.updateExercise(userId: ownerId, exerciseId: id, category: 'x'),
        throwsA(isA<NotFound>()),
      );
    });

    test('a nonexistent exercise id throws NotFound', () async {
      await expectLater(
        h.db.updateExercise(
          userId: ownerId,
          exerciseId: '00000000-0000-7000-8000-000000000000',
          category: 'x',
        ),
        throwsA(isA<NotFound>()),
      );
    });
  });

  group('setExerciseMedia', () {
    final asset = {'link': 'https://cdn.test/asset.mp4', 'width': 640, 'height': 480};
    final thumbnail = {'link': 'https://cdn.test/thumb.jpg', 'width': 160, 'height': 120};

    test('writes asset and thumbnail onto the global exercise matched by key', () async {
      final name = h.uniqueName('Media');
      final id = await h.seedGlobalExercise(name: name);

      await h.db.setExerciseMedia(key: DatabaseTestBase.slug(name), asset: asset, thumbnail: thumbnail);

      final row = findEx((await h.db.getExercises(ownerId))['exercises'] as List, id);
      expect(row!['asset'], asset);
      expect(row['thumbnail'], thumbnail);
    });

    test('throws NotFound when no global exercise has that key', () async {
      await expectLater(
        h.db.setExerciseMedia(key: DatabaseTestBase.slug(h.uniqueName('Missing')), asset: asset, thumbnail: thumbnail),
        throwsA(isA<NotFound>()),
      );
    });

    test('a user-owned exercise never matches: keys belong to globals only', () async {
      final name = h.uniqueName('UserOwnedMedia');
      await h.db.createExercise(userId: ownerId, name: name, category: 'Barbell', target: 'Chest');
      // Owned rows carry no key (and the query requires user_id IS NULL).
      await expectLater(
        h.db.setExerciseMedia(key: DatabaseTestBase.slug(name), asset: asset, thumbnail: thumbnail),
        throwsA(isA<NotFound>()),
      );
    });
  });
}

class _Harness extends DatabaseTestBase;
