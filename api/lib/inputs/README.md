# Inputs

Typed request models. The convention is borrowed from FastAPI / Pydantic, ported onto Relic.

## Why

A Relic handler signature is `Future<Model> Function(Request)`. Without help, that puts request parsing, shape validation, type coercion, and 400 generation inside every handler:

```dart
Future<Comment> createComment(Request req) async {
  final body = await req.json();
  final targetTypeRaw = body['target_type'] as String?;
  if (targetTypeRaw == null) throw BadRequest(...);
  // ... 20 more lines ...
}
```

Same template every endpoint, easy to drift. The goal is to do for Relic what FastAPI does for Starlette: **declare the input shape as a typed dataclass, let the framework decode/validate.**

## Shape

For each endpoint, declare a class with:

- All fields typed (no `dynamic`).
- A private positional constructor.
- A `static Future<T> fromRequest(Request, {...})` factory that pulls JSON / query / path bits, validates, returns the populated object.

```dart
class CommentCreateIn {
  final CommentTarget targetType;
  final String targetId;
  final String body;

  const CommentCreateIn._({
    required this.targetType,
    required this.targetId,
    required this.body,
  });

  static Future<CommentCreateIn> fromRequest(Request req) async {
    final json = await req.json();
    return CommentCreateIn._(
      targetType: json.parsed('target_type', CommentTarget.fromString),
      targetId: json.string('target_id'),
      body: json.string('body', maxLength: 5000),
    );
  }
}
```

Route handlers then read:

```dart
Future<Comment> createComment(Request req) async {
  final input = await CommentCreateIn.fromRequest(req);
  await _assertCanAccessTarget(req, targetType: input.targetType, targetId: input.targetId);
  return req.commentService.createComment(
    authorId: req.userId,
    targetType: input.targetType,
    targetId: input.targetId,
    body: input.body,
  );
}
```

All validation lives in the input class. The handler is plumbing.

## Naming

Per-endpoint, not per-resource: `CommentCreateIn`, `CommentEditIn`, `CommentsListQuery`, `DeviceRegisterIn`. Different endpoints have different shapes — a single `CommentIn` with optional fields hides "which fields apply where" and forces re-validation in every handler.

Suffix conventions:

- `…In` — JSON body input (POST/PUT).
- `…Query` — pure query-string input (GET).
- Mixed (body + path param) — still `…In`; pass the path param as a named arg on `fromRequest`.

## Parsing helpers

`parse.dart` adds **unnamed extensions** on `Map<String, dynamic>` (JSON body) and `Map<String, String>` (query params). They use pattern matching — happy path returns, everything else throws `BadRequest`:

```dart
extension on Map<String, dynamic> {
  String string(String field, {int? maxLength}) {
    return switch (this[field]) {
      String s when s.isNotEmpty && (maxLength == null || s.length <= maxLength) => s,
      _ => throw BadRequest(reason: ...),
    };
  }
}
```

Current set: `.string(...)`, `.parsed<T>(field, parser)`, `.mapping(...)`, plus query-side variants and `.integer(field, {min, max, defaultValue})`. Extend in place; one happy-path branch per type, default branch throws with a useful message.

## Path parameters

Pass through `fromRequest`'s named args:

```dart
static Future<CommentEditIn> fromRequest(Request req, {required String commentId}) async { … }
```

The route handler:

```dart
Future<Comment> editComment(Request req) =>
    editCommentById(req, req.rawPathParameters[#commentId]!);
```

The `…ById` wrapper exists so tests can call `editCommentById(req, 'c-1')` directly (Relic's routing context isn't settable in tests). See `test/helpers/README.md`.

## Outputs and auto-400

The other half of the FastAPI feel:

- Return types are `Model` subclasses (`Comment`, `Paginated<Comment>`, …). `_handler` in `bin/main.dart` wraps the result in `JsonResponse.ok` and calls `Model.toMap`.
- `throw NoContent()` becomes 204. `throw BadRequest(...)`, `Forbidden(...)`, `NotFound(...)` become the appropriate `ApiException` → 400/403/404.
- Uncaught `TypeError` and `FormatException` (e.g., a client sent a number where a string was expected and slipped past validation) are caught in `_handler` and turned into 400s automatically. Means the parse layer doesn't have to guard every cast — sloppy client input becomes a clean 400.

## Pagination

`Page<T>` lives in `heart_models`. It's the service-layer page result: `{items, hasMore}`. The DB layer fetches `limit + 1` rows so `hasMore` is authoritative without a follow-up query.

`Paginated<T>` in `api/lib/models/pagination.dart` is the HTTP wrapper:

```dart
return Paginated<Comment>.from(page, itemsKey: 'comments', cursorOf: (c) => c.id);
```

Critically, `cursor` is **only included in the response body when `hasMore` is true**. Clients don't have to make a wasted round trip to discover the list is exhausted.

Every list endpoint takes the same query shape — `?cursor=<opaque>&limit=N` — parsed and bounds-checked by `PageQuery.fromRequest(req)` (see `pagination.dart`). `cursorOf` derives the next cursor from the last item's `id`. This relies on the keyset ordering key being the item's serialized `id`, so list queries order by the same `id` they return.

That holds for every list ordered by creation (uuidv7 is chronological). A list the user has **arranged** cannot use it: the sort key is `order`, which isn't unique, so the id has to ride along as a tie-break and the cursor must carry both. `OrderedCursor` in `heart_models` is that pair, serialized `<order>:<id>` and still opaque to clients; `TemplateListQuery` parses it and `getMyTemplates` emits it via `cursorOf`. Templates are the only such list today — reach for it if you add another, rather than paginating a user-ordered list on id and quietly ignoring their arrangement.

## Adding a new endpoint

1. Add a `<Verb><Noun>In` (or `…Query`) class in the matching `lib/inputs/<domain>.dart`.
2. Use the parse helpers in `fromRequest` — extend `parse.dart` only if you need a new primitive (date, email, URL).
3. Route handler reads the input, calls the service, returns a `Model`.
4. Write a test in `test/routes/<domain>_test.dart` using `jsonRequest(...)` from `test/helpers/request.dart`.

The framework path (`bin/main.dart` → `_handler` → `JsonResponse` / `ApiException` mapping) does the rest.