import 'dart:io';

import 'package:heart/db/db.dart';
import 'package:postgres/postgres.dart' hide Connection;

/// Base for `db`-tagged integration tests. Owns the connection [pool] + the real
/// [Database], and provides shared seed builders so each suite only writes the
/// fixtures unique to it.
///
/// Seeded profiles and global exercises are tracked and removed automatically in
/// [teardownDatabase] — deleting a profile cascades to everything it owns
/// (workouts, images, connections, templates, …), then the orphaned global
/// exercises are cleaned up.
abstract class DatabaseTestBase {
  late Pool pool;
  late Database db;

  /// Unique per run, so ids/names don't collide across repeated local runs or
  /// with rows from sibling suites sharing the database.
  late final String token;

  final List<String> _seededProfiles = [];
  final List<String> _seededExercises = [];
  var _seq = 0;

  Future<void> setupDatabase() async {
    // Standard PG* env vars with local defaults, so the same harness works on a
    // dev machine (peer auth as the OS user) and in CI (PGUSER=postgres).
    final env = Platform.environment;
    pool = Pool.withEndpoints(
      [
        Endpoint(
          host: env['PGHOST'] ?? 'localhost',
          port: int.parse(env['PGPORT'] ?? '5432'),
          database: env['PGDATABASE'] ?? 'heart',
          username: env['PGUSER'] ?? env['USER'],
          password: env['PGPASSWORD'],
        ),
      ],
      // Local Postgres has no TLS; the default requires it.
      settings: const PoolSettings(
        maxConnectionCount: 5,
        applicationName: 'heart-test',
        sslMode: SslMode.disable,
      ),
    );
    db = Database(pool: pool);
    token = DateTime.now().microsecondsSinceEpoch.toString();
  }

  Future<void> teardownDatabase() async {
    await cleanupSeed();
    await pool.close();
  }

  Future<Result> exec(String sql, [Map<String, dynamic> params = const {}]) {
    return pool.execute(Sql.named(sql), parameters: params);
  }

  /// Runs [sql] and returns the `id` column of the first row as a string.
  Future<String> insertId(String sql, Map<String, dynamic> params) async {
    final rows = await exec(sql, params);
    return rows.first.toColumnMap()['id'].toString();
  }

  /// A unique text id (for `profiles.id` and other TEXT keys).
  String uid(String prefix) => 'itest-$prefix-$token-${_seq++}';

  /// A unique human-readable name (e.g. for exercises, templates).
  String uniqueName(String prefix) => 'ITest $prefix $token ${_seq++}';

  /// Inserts a profile and tracks it for cascade cleanup. Pass [id] to control
  /// it (when the test references the same user across cases), else one is
  /// generated.
  Future<String> seedProfile({String? id}) async {
    final pid = id ?? uid('user');
    await exec(
      'INSERT INTO profiles (id, username, email) VALUES (@id, @u, @e) ON CONFLICT (id) DO NOTHING',
      {'id': pid, 'u': 'u_$pid', 'e': '$pid@test.local'},
    );
    _seededProfiles.add(pid);
    return pid;
  }

  /// Registers a profile created outside [seedProfile] (e.g. one made via the
  /// service under test) so it gets the same cascade cleanup in teardown.
  void trackProfile(String id) => _seededProfiles.add(id);

  /// Connects two profiles (default: active peers) so connection-gated queries
  /// allow [initiator] to act on [target]. Pass [status] to seed a connection
  /// that exists but is not live — `pending`, `severed`, `blocked` — which the
  /// gates must refuse.
  Future<void> seedConnection({
    required String initiator,
    required String target,
    String role = 'PEER',
    String domain = 'fitness',
    String status = 'active',
  }) async {
    await exec(
      'INSERT INTO connections (initiator_id, target_id, initiator_role, target_role, domain, status) '
      'VALUES (@i, @t, @r, @r, @d, @s) ON CONFLICT DO NOTHING',
      {'i': initiator, 't': target, 'r': role, 'd': domain, 's': status},
    );
  }

  /// Inserts a global exercise (user_id NULL) and tracks it for cleanup. Pass
  /// [name] when a test needs a specific display name; the content key is
  /// derived from it (global rows must carry one).
  Future<String> seedGlobalExercise({String? name}) async {
    final n = name ?? uniqueName('Ex');
    final id = await insertId(
      'INSERT INTO exercises (key, name, category, target) VALUES (@k, @n, @c, @t) RETURNING id',
      {'k': slug(n), 'n': n, 'c': 'Barbell', 't': 'Chest'},
    );
    _seededExercises.add(id);
    return id;
  }

  /// The content slug a [seedGlobalExercise] row carries for [name].
  static String slug(String name) =>
      name.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');

  /// Inserts a workout owned by [userId]. With [withExercise], also links one
  /// global exercise + one set so reads return a populated workout.
  Future<String> seedWorkout({
    required String userId,
    String name = 'Original',
    DateTime? start,
    DateTime? end,
    bool withExercise = false,
  }) async {
    final workoutId = await insertId(
      'INSERT INTO workouts (user_id, name, started_at, completed_at) VALUES (@u, @n, @s, @e) RETURNING id',
      {'u': userId, 'n': name, 's': start ?? DateTime.utc(2026, 7, 20, 18), 'e': end ?? DateTime.utc(2026, 7, 20, 19)},
    );
    if (withExercise) {
      final exerciseId = await seedGlobalExercise();
      final weId = await insertId(
        'INSERT INTO workout_exercises (workout_id, exercise_id, exercise_order) VALUES (@w, @e, 0) RETURNING id',
        {'w': workoutId, 'e': exerciseId},
      );
      await exec(
        'INSERT INTO exercise_sets (workout_exercise_id, weight, reps, set_order) VALUES (@we, 100, 5, 0)',
        {'we': weId},
      );
    }
    return workoutId;
  }

  /// Deletes seeded profiles (cascading to their owned rows) then the orphaned
  /// global exercises. Called by [teardownDatabase]; safe to call directly.
  Future<void> cleanupSeed() async {
    if (_seededProfiles.isNotEmpty) {
      await exec('DELETE FROM profiles WHERE id = ANY(@ids)', {'ids': _seededProfiles});
    }
    for (final id in _seededExercises) {
      await exec('DELETE FROM exercises WHERE id = @id::uuid', {'id': id});
    }
  }
}
