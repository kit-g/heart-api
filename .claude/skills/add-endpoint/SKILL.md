---
name: add-endpoint
description: Add a new HTTP endpoint to the Dart API (api/). Use whenever adding or substantially changing a route — it enumerates every file that must change and the order, so nothing is silently skipped. Triggers: "add an endpoint", "new route", "expose X over the API", "POST/GET/PUT/DELETE /something".
---

# Adding an API endpoint

The API wires a route across ~8 files. Miss one and it fails late (compile error, DI `StateError` at runtime, or a missing mock). Follow this order. Read `api/lib/inputs/README.md` and `api/test/helpers/README.md` first if you haven't this session.

## Conventions that are non-negotiable

- **snake_case** for DB rows (`fromRow`, SQL columns). **camelCase** for JSON (`toMap`, input parsing). Don't mix.
  - The snake_case half governs **column names only** — *not* the contents of a `jsonb` blob. Blobs are stored camelCase (`profiles.settings`, `goals.stages`, `exercises.movement`), so a query can ship the column straight to the client and the model needs only `fromJson`/`toMap` — no `Storable`/`fromRow`/`toRow` pair, which would be an identical no-op.
  - Whatever *writes* the blob emits camelCase. Converting per-read instead is recomputing a constant; a generic recursive `_camel(jsonb)` measured ~20 ms on a full-library read (~85% of the query), and a hand-enumerated `jsonb_build_object` silently drops keys added later.
  - When a write-side script and a Dart model share a blob contract, pin it with a test on **both** sides. A key mismatch never throws — it reads as the field's default, so the failure is silent and wrong rather than loud.
- Route handlers are `Future<Model> Function(Request)`. Pull inputs via a typed input class, call a service, return a `Model`. No `req.json()` parsing inside handlers.
- Control flow is throws: `throw NoContent()` → 204, `BadRequest`/`Forbidden`/`NotFound` → status. `apiHandler` (`lib/core/handler.dart`) already maps `TypeError`/`FormatException` → 400, `UnimplementedError` → 501, everything else → 500.
- List responses use `Paginated<T>.from(page, ...)` — never emit a bare `cursor`. Service returns `Page<T>` (fetch `limit + 1` for authoritative `hasMore`). The cursor is the last item's `id`; keep the keyset ORDER BY on that same `id` so `cursorOf: (x) => x.id` is correct.
- Query behavior is covered by `db`-tagged **integration tests** against real Postgres — not by route tests (which mock the service) nor pgtap (schema/signatures only). Any non-trivial SQL you write is otherwise untested.

## Steps

1. **Input class** — `api/lib/inputs/<domain>.dart` (a `part of 'inputs.dart'`). `<Verb><Noun>In` for bodies, `<Noun>Query` for GET query params. Private positional ctor + `static Future<T> fromRequest(Request, {pathParams})`. Use the `Map` parse extensions (`.string`, `.parsed`, `.integer`, `.mapping`). Add the `part` line to `inputs.dart` if the file is new.

2. **Service interface** — `shared/heart_models/lib/src/services/<domain>.dart`, exported from `heart_models.dart`. Methods return domain models or `Page<T>`.

3. **SQL** — add query strings to `api/lib/db/queries.dart` (use the `.toSql()` extension).

4. **DB mixin** — `api/lib/db/<domain>.dart` as `mixin _<Domain> on _DatabaseBase implements <Domain>Service`. Pagination methods fetch `limit + 1` and return `Page(items: …, hasMore: …)`.

5. **Register the mixin in `api/lib/db/db.dart`** — THREE edits: the `part '<domain>.dart';` line, the `with _<Domain>` in the class header, and the `<Domain>Service` in `implements`. (Easy to do 1 of 3.)

6. **DI middleware** — `api/lib/middleware/database.dart`, THREE spots: the `ContextProperty`, the `Middleware <domain>Db({required <Domain>Service db})`, and the `get`/`set` on the `DatabaseContext` extension.

7. **Route handler** — `api/lib/routes/<domain>.dart`. For path-param routes, split into `handler(req) => handlerById(req, req.rawPathParameters[#id]!)` + `handlerById(req, id)` so tests can hit the `…ById` form directly.

8. **Register route** — `api/lib/routes/index.dart` (`('/path', .verb): domain.handler`) AND wire the DB middleware in `buildApp` (`api/lib/core/app.dart`), e.g. `..use('/path', <domain>Db(db: database))`. That's the single wiring spot — `bin/main.dart` just builds the real deps and calls `buildApp` + `serve()`. Add to `_publicRoutes` only if it bypasses auth.

9. **Mocks** — if you added a service interface, add it to `@GenerateMocks` in `api/test/mocks.dart`, then **`cd api && dart run build_runner build --delete-conflicting-outputs`**. Skipping this is the #1 silent miss.

10. **Route test** — `api/test/routes/<domain>_test.dart`. Two styles live here; both mock the service, so neither covers SQL:
    - **Direct (default).** `jsonRequest(...)`/`bareRequest(...)` from `test/helpers/request.dart`, mocks wired onto the request via the context setters, call the handler function, assert throws with `expect(() => handler(req), throwsA(isA<NoContent>()))` etc. Fast; proves the handler's own wiring. Use this for a new endpoint by default.
    - **HTTP harness (integration).** `AppHarness` (`test/helpers/app_harness.dart`) boots the real `buildApp` on a loopback port and drives genuine HTTP through the whole chain — router, middleware order, auth, and `apiHandler` status mapping. Reach for it when the *integration* is the point: a new public route that must bypass auth, middleware ordering, or that a path/verb is actually registered. `await AppHarness.start()` → stub `app.db`/`app.storage`/`app.config` → `app.send('GET', '/path')` returns `(status, body)`. Note it can't reach handler branches that `new` up an AWS client inline (`Scheduler`/`Sns`/`Sqs`) — those need real AWS or client injection.

11. **DB integration test** (whenever you add or change a query — required for anything non-trivial: CTEs, pagination, cursor logic, multi-table writes) — `api/test/db/<domain>_db_test.dart`, tagged `@Tags(['db'])`, extending `DatabaseTestBase` (`test/db/db_test_utility.dart`, which connects via `PG*` env vars). Seed prerequisites with raw SQL, call the real `db.<method>(...)`, assert on the returned model / `Page` (`hasMore`, and the next-page cursor by paginating with a `limit` and passing the returned cursor back). Clean up in `tearDownAll` — deleting the seeded profiles cascades to everything owned. `dart_test.yaml` skips the `db` tag so the default (DB-less) `dart test` stays green.

    **The cascade teardown breaks on user-owned exercises.** `template_exercises.exercise_id` (and `workout_exercises.exercise_id`) is **RESTRICT**, not CASCADE. Deleting a seeded profile cascades to its templates *and* its exercises, and if a `template_exercises` row still references one, the whole `tearDownAll` throws — failing the run after every test passed. Every existing test dodges this by seeding **global** exercises (`seedGlobalExercise`, `user_id IS NULL`), which are deleted separately after the profiles, so the trap stays invisible until you seed a user-owned one. If your case needs a user-owned exercise in a template (e.g. exercising a copy-on-share branch), delete the templates yourself at the end of the test:

    ```dart
    await h.exec('DELETE FROM templates WHERE user_id = ANY(@ids)', {'ids': [coach, student]});
    ```

    Related: a **global** exercise resolves by name for the target user rather than being copied, so a test aiming at a copy-into-library branch must seed the source as **coach-owned** or the branch never runs and the assertion silently tests nothing.

12. **Verify** — `cd api && dart analyze && dart test` (both clean), then the DB tests against a local `heart` DB with migrations applied: `dart test --run-skipped -t db test/db`. CI runs the unit tests in the `dart-test` job and the DB tests in `db-test`.

## Self-check before declaring done

- [ ] `dart analyze` clean, `dart test` green
- [ ] new/changed query has a `db`-tagged integration test, passing via `dart test --run-skipped -t db test/db`
- [ ] new service (if any) is in `mocks.dart` AND build_runner re-run
- [ ] `db.dart` got all three edits (part / with / implements)
- [ ] `database.dart` got all three edits (property / middleware / extension)
- [ ] route registered in BOTH `index.dart` and `buildApp` (`lib/core/app.dart`, middleware)
- [ ] response is camelCase; list responses use `Paginated`
- [ ] if the endpoint has side effects (queue/scheduler/FCM), it uses `req.events.publish(...)`, not a raw `Sqs` in the handler