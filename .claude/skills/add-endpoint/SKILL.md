---
name: add-endpoint
description: Add a new HTTP endpoint to the Dart API (api/). Use whenever adding or substantially changing a route — it enumerates every file that must change and the order, so nothing is silently skipped. Triggers: "add an endpoint", "new route", "expose X over the API", "POST/GET/PUT/DELETE /something".
---

# Adding an API endpoint

The API wires a route across ~8 files. Miss one and it fails late (compile error, DI `StateError` at runtime, or a missing mock). Follow this order. Read `api/lib/inputs/README.md` and `api/test/helpers/README.md` first if you haven't this session.

## Conventions that are non-negotiable

- **snake_case** for DB rows (`fromRow`, SQL columns). **camelCase** for JSON (`toMap`, input parsing). Don't mix.
- Route handlers are `Future<Model> Function(Request)`. Pull inputs via a typed input class, call a service, return a `Model`. No `req.json()` parsing inside handlers.
- Control flow is throws: `throw NoContent()` → 204, `BadRequest`/`Forbidden`/`NotFound` → status. `_handler` in `bin/main.dart` already maps `TypeError`/`FormatException` → 400.
- List responses use `Paginated<T>.from(page, ...)` — never emit a bare `cursor`. Service returns `Page<T>` (fetch `limit + 1` for authoritative `hasMore`).

## Steps

1. **Input class** — `api/lib/inputs/<domain>.dart` (a `part of 'inputs.dart'`). `<Verb><Noun>In` for bodies, `<Noun>Query` for GET query params. Private positional ctor + `static Future<T> fromRequest(Request, {pathParams})`. Use the `Map` parse extensions (`.string`, `.parsed`, `.integer`, `.mapping`). Add the `part` line to `inputs.dart` if the file is new.

2. **Service interface** — `shared/heart_models/lib/src/services/<domain>.dart`, exported from `heart_models.dart`. Methods return domain models or `Page<T>`.

3. **SQL** — add query strings to `api/lib/db/queries.dart` (use the `.toSql()` extension).

4. **DB mixin** — `api/lib/db/<domain>.dart` as `mixin _<Domain> on _DatabaseBase implements <Domain>Service`. Pagination methods fetch `limit + 1` and return `Page(items: …, hasMore: …)`.

5. **Register the mixin in `api/lib/db/db.dart`** — THREE edits: the `part '<domain>.dart';` line, the `with _<Domain>` in the class header, and the `<Domain>Service` in `implements`. (Easy to do 1 of 3.)

6. **DI middleware** — `api/lib/middleware/database.dart`, THREE spots: the `ContextProperty`, the `Middleware <domain>Db({required <Domain>Service db})`, and the `get`/`set` on the `DatabaseContext` extension.

7. **Route handler** — `api/lib/routes/<domain>.dart`. For path-param routes, split into `handler(req) => handlerById(req, req.rawPathParameters[#id]!)` + `handlerById(req, id)` so tests can hit the `…ById` form directly.

8. **Register route** — `api/lib/routes/index.dart` (`('/path', .verb): domain.handler`) AND wire the DB middleware in `bin/main.dart` (`..use('/path', <domain>Db(db: _database))`). Add to `_publicRoutes` only if it bypasses auth.

9. **Mocks** — if you added a service interface, add it to `@GenerateMocks` in `api/test/mocks.dart`, then **`cd api && dart run build_runner build --delete-conflicting-outputs`**. Skipping this is the #1 silent miss.

10. **Test** — `api/test/routes/<domain>_test.dart` using `jsonRequest(...)`/`bareRequest(...)` from `test/helpers/request.dart`. Wire mocks onto the request via the context setters. Assert throws with `expect(() => handler(req), throwsA(isA<NoContent>()))` etc.

11. **Verify** — `cd api && dart analyze && dart test`. Both must be clean.

## Self-check before declaring done

- [ ] `dart analyze` clean, `dart test` green
- [ ] new service (if any) is in `mocks.dart` AND build_runner re-run
- [ ] `db.dart` got all three edits (part / with / implements)
- [ ] `database.dart` got all three edits (property / middleware / extension)
- [ ] route registered in BOTH `index.dart` and `main.dart` (middleware)
- [ ] response is camelCase; list responses use `Paginated`
- [ ] if the endpoint has side effects (queue/scheduler/FCM), it uses `req.events.publish(...)`, not a raw `Sqs` in the handler