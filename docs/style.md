# House style

What the linter cannot say. `make lint` enforces the mechanical part (the root
`analysis_options.yaml`: trailing commas, const, single quotes, declaring
parameters, no `print`; `ruff` for Python; `terraform fmt`); this page is the
rest — the shapes that get a change sent back even when analysis is clean.
Each entry is a no-no and the form that replaces it. Add to it when a review
finds a new one. The FE has its own (`docs/style.md` in `heart-of-yours`); the
two overlap on purpose where the language is the same.

## Boundaries

**Validate at the edge, trust the inside.** Shape and type checks happen once,
in an `inputs/` class (`<Verb><Noun>In`, `<Noun>Query`: private positional
constructor, `static Future<T> fromRequest`) or at the AWS event boundary.
Nothing between modules re-validates.

```dart
// no — parsing inside the handler
Future<Goal> createGoal(Request req) async {
  final body = await req.json();
  final metric = body['metric'] as String?;
  if (metric == null) throw BadRequest(reason: 'metric required');
  …

// yes
Future<Model> createGoal(Request req) async {
  final input = await GoalCreateIn.fromRequest(req);
  return req.goalService.createGoal(input.goal, req.userId);
}
```

**Handlers do three things**: decode the input, call a service, return a
`Model`. Control flow is `throw` — `NoContent`, `BadRequest`, `Forbidden`,
`NotFound` — and `apiHandler` maps it. No `try`/`catch` unless the catch
does something useful; a catch that logs and rethrows, or converts one
exception into a vaguer one, is a finding.

**Every error has a stable `code`.** `reason` is prose and may be reworded;
`code` is what a client branches on and never changes. A failure a client
must tell apart gets its own code (`goal_limit`, `id_taken`,
`anonymous_account`), not a distinctive sentence.

**No backwards-compat shims in `api/`.** Client and server ship together.
The one place compatibility is a rule is `shared/heart_models`: additive
only, bumped in the same commit — CLAUDE.md, *Package versioning*.

**Shapes live in exactly one place.** Anything the client ever sees is a
`heart_models` model. Anything only the server uses — service
sub-interfaces, request wrappers, error models — is in `api/lib/models`.
A server-only concern that changes a `heart_models` signature is the wrong
fix, even when it is the shortest one.

## Dart

**Match on shape, don't cast and branch.** Parsing and dispatch are `switch`
expressions over patterns, positive case first. No multi-line ternaries, no
`x != null ? a : b`; a one-line `??` is fine.

```dart
// no
final id = json['id'] == null
    ? null
    : (json['id'] is String && isUuidV7(json['id']) ? json['id'] as String : throw BadRequest(…));

// yes
final id = switch (json['id']) {
  null => null,
  final String id when isUuidV7(id) => id,
  _ => throw const BadRequest(reason: 'id must be a UUIDv7'),
};
```

**Declaring constructors.** `const new({required this.id})`,
`factory fromJson(Map json)`, `new _()` for the private one. Not the
pre-3.13 `ClassName({required this.id})` form — the `use_declaring_parameters`
lint catches the parameter half, this covers the rest.

**Private by default.** SQL constants (`_listExercises`), mixins
(`_Goals`), helpers and test fakes are `_named` unless something outside the
file needs them. Don't widen visibility to make a test easier; test through
the route or the `Database`.

**Names carry the WHAT; comments carry the WHY.** A comment explains the
constraint, the bug this shape avoids, the thing that looks redundant and
isn't — the `DISTINCT` guard in a join, the reason a retry is safe. Never
what the next line does. This applies inside SQL strings too; the long
queries are documented where the subtlety is.

**Casing is by layer, and it never mixes.** snake_case for anything the
database sees (`fromRow`, column names, SQL parameters via `@snake_case` is
fine either way but be consistent within a query); camelCase for JSON
(`toMap`, `fromJson`, input parsing). A `jsonb` blob is camelCase inside,
because it ships to the client verbatim. Identifiers name the thing: an
exercise is its `id`, `key` is the content handle, `name` is display copy.

**Lists are `Paginated<T>`**, built from a `Page<T>` the service returns
after fetching `limit + 1`; the cursor is the last item's `id` and the
keyset `ORDER BY` is on that same column. Never a bare `cursor` field.

## SQL

**One round trip.** Anything touching more than one table is a single
multi-CTE statement (`WITH _a AS (…), _b AS (…) SELECT …`), never a
sequence of queries with logic in Dart between them.

**`RETURNING`, always.** A write that could hand back the new state and
doesn't is a bug waiting for a second query.

**Authorization is in the query, via the `forbidden` sentinel.** Empty
result → 404, one row with `forbidden = true` → 403, otherwise data. Not a
separate ownership `SELECT` first.

**Partial updates are `coalesce(@col, col)`.** Pass `null` for "unchanged".

**Non-trivial SQL gets a `db`-tagged test** (`api/test/db/*_db_test.dart`,
`dart test --run-skipped -t db`). Route tests mock the service and prove
nothing about a query; pgtap covers schema and signatures only. A query
with neither is untested, however obvious it looks.

**Migrations are new files, in house style** — `add-migration` skill:
dated name, `DROP … IF EXISTS` then `CREATE … IF NOT EXISTS` so dev can
replay, snake_case, `COMMENT ON` every object, short constraint names.
Never edit one that has been applied anywhere.

## Python

`ruff` owns formatting and imports (single quotes, 120 columns). Beyond it:

- **Dependencies through `pyproject.toml` and `uv lock`**, never `pip`;
  CI installs from the lockfile only.
- **Flat-import style per Lambda** (`from events import …`): each service is
  a zip root, and `pytest` runs each service in its own process for that
  reason. Don't reach across services.
- **Events are frozen dataclasses with `from_dict`**, dispatched by a
  `match` on type — `firebase/README.md`, *Add a new event*.
- **Scripts are entrypoints CI calls.** A check that exists as a script is
  never re-implemented inline in a workflow (`ci-workflows` skill).

## Terraform

- **Provider versions are pinned in each environment's `providers.tf`**,
  never in a shared `stack/` or `modules/` file — a constraint there makes
  Dependabot open the same PR once per environment.
- **`terraform fmt` clean, `make test-tf` green.** Agents plan; the owner
  applies.
- **Paths**: sibling modules by relative path (`../../stacks/api`); the repo
  root from inside a stack is `${path.module}/../../../../`.
- **Resources are `${var.name_prefix}-<thing>`**; the Lambda function name
  itself is the bare prefix.
- **Comments say why**, same rule as Dart — a lifecycle `ignore_changes`, a
  deliberate exception to a pattern, a value that must match another file.

## Naming things outside the code

- **The repos are `heart-api` and `heart-of-yours`.** Issues are
  `heart-api#66`, `heart-of-yours#92`. No `kit-g/` prefix in prose, docs,
  comments, changelogs or tickets; the owner appears only where a tool needs
  the full slug — a `github.com` URL, `gh -R`, an OIDC `repo:` subject.
- **Design docs are `docs/YYYY-MM-DD.slug.md`**, written from the code as it
  stands ("nothing here is a proposal unless it says so"), with a *Gaps*
  section. Code-adjacent docs go in the nearest `README.md`.
- **Changelog entries say what a pull brings in**, for the app side that
  reads them — one line per public change, linking the ticket.

## Leftovers

No `TODO(agent)`, no commented-out code, no debug prints, no scratch files
at the repo root. A genuine open end goes in the handoff, not the source.
