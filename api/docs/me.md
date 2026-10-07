# Heart's developer API: reading your own training

Your training log, readable by your own scripts, spreadsheets and AI assistants. It's free and
read-only. **It has no health data in it, because Heart never has any:** heart rate, sleep, body
weight and the rest stay on your phone, in Apple Health or Health Connect. Workout `calories` is an
estimate from the exercises and the weight you entered, never a watch reading.

```sh
curl https://api.heart-of.me/v1/me/workouts?limit=5 \
  -H "Authorization: Bearer hrt_…" \
  -H "User-Agent: my-sheet-sync/1.0"
```

## Tokens

Create a token in the app under Settings. You need a signed-in account; anonymous use has nothing on
the server to read. You see a token's secret once, when you create it. Heart stores only a digest
of it. You can hold five active tokens, each living a year or until you revoke it.

Send it as a bearer token. A missing, unknown, revoked or expired token gets the same answer:

```json
401 {"error": "unauthorized", "code": "invalid_token", "reason": "…"}
```

**Please set a User-Agent that names your tool.** It isn't required, but it helps us see what
people build.

## Limits

20 requests a minute and 200 a day per account, shared by all of its tokens. Past either one:

```json
429 {"error": "too many requests", "code": "rate_limited", "reason": "…", "retryAfter": 41}
```

with a `Retry-After` header in seconds. Free limits never go down.

## Routes

All `GET`, all about the account the token belongs to. Paginated lists carry a `cursor` while
there's more: pass it back as `?cursor=` for the next page. No `cursor` means the last page.
`limit` is 1–100 (default 30). Workouts come newest first.

| Route                     | Returns                                                                                          |
|---------------------------|--------------------------------------------------------------------------------------------------|
| `/me`                     | `id`, `username`, `unitSystem` (`metric`/`imperial`, when set), and `counts` of workouts, templates, folders, goals and custom exercises |
| `/me/workouts`            | `{workouts, cursor}`: each workout with its exercises, sets, notes and image URLs       |
| `/me/workouts/:workoutId` | one workout                                                                                      |
| `/me/workouts/changes`    | `{workouts, deleted, cursor, hasMore}`: what changed since `?since=<cursor>`, oldest first (see *Polling*) |
| `/me/records`             | `{records}`: personal records per exercise, the same ones the app shows; `?exerciseId=` for one |
| `/me/exercises`           | `{exercises}`: your custom exercises (a `glossary` key rides along; ignore it). Library exercises come embedded in workouts and templates  |
| `/me/templates`           | `{templates, cursor}`, in your order; `?folder=<id>`, or `?folder=none` for unfiled ones                        |
| `/me/template-folders`    | `{folders}`                                                                                      |
| `/me/goals`               | `{goals}`; `?archived=true` for archived ones. Goals backed by health data carry their definition only; their progress lives on your phone |

## Polling

To keep a copy in sync, poll `/me/workouts/changes` instead of re-reading the history. Without
`since` it starts from the beginning. After that, pass back the `cursor` you were given. Each change
is a whole workout as it stands now (in `workouts`) or the id of one that was deleted (in `deleted`,
with `deletedAt`). While `hasMore` is true, ask again straight away. When nothing changed, you get
empty lists and the same cursor, so keep it. A `400` with `code: "stale_cursor"` means the cursor
can't be read any more (the database behind the API was moved): start again without `since`.

Changes show up as soon as they're saved, or later while a longer save (a big import) that began
earlier is still running, so that save can't land behind a cursor you already hold. Polling more often than every few
minutes gains nothing and uses up the daily limit.

## AI assistants (MCP)

The same token connects an AI assistant to your log over MCP, read-only, at
`https://api.heart-of.me/v1/mcp`. In Claude Code:

```sh
claude mcp add --transport http heart https://api.heart-of.me/v1/mcp \
  --header "Authorization: Bearer hrt_…"
```

In Cursor or any client with a JSON config:

```json
{"mcpServers": {"heart": {"url": "https://api.heart-of.me/v1/mcp", "headers": {"Authorization": "Bearer hrt_…"}}}}
```

The assistant can read your profile, workouts, templates, folders, goals and custom exercises, and
nothing else; it can't change anything. Only its data calls count against your limits, not the
listing it does at the start of each conversation. Connecting from Claude or ChatGPT by signing in
instead of pasting a token is coming.

## Export

`GET /me/export?format=strong` downloads your whole history as a CSV in Strong's export format.
That's the format other apps import, Heart included. Weights and distances are in your unit
(kilograms and kilometres, or pounds and miles), and times are in UTC. A large history answers
`303` with a link that works for 15 minutes. One export a day; a second answers
`429 export_limit`.

```sh
curl -L "https://api.heart-of.me/v1/me/export?format=strong" -H "Authorization: Bearer hrt_…" -o heart.csv
```

## Units

Weights are in kilograms and distances in kilometres, whatever your display unit. Times are
ISO 8601 in UTC.

## Compatibility

Fields and routes may be added; none will be renamed or removed under `/me`. Ignore fields you don't
know.
