---
name: release
description: Draft the notes for a prod API release (a `v*` tag) — the compatibility note CLAUDE.md requires, the developer-facing changelog for the /me, MCP and OAuth surfaces, and the ordered pre-tag checklist — from the diff since the last tag, into release_notes/v<version>.md, which becomes the tag message and the GitHub release. Triggers: "release", "cut a release", "tag", "prod deploy", "release notes", "compatibility note", "what's in this release".
---

# Releasing the API

A prod release is a `v*` tag on `main`: `deploy-api-prod.yml` deploys it, then publishes
`release_notes/<tag>.md` as the GitHub release. The file is the one record of the release. It is
committed to `main` **before** the tag and reused as the tag's message, so nothing is written twice.

The release has three readers, so the file has three sections:

| Section           | Reader                                 | Question it answers                                   |
|-------------------|----------------------------------------|-------------------------------------------------------|
| **Compatibility** | installed app builds (CLAUDE.md floor) | what changed in any contract, and who is still served |
| **Developers**    | people on `/me`, MCP and OAuth         | what they can now do, and what behaves differently    |
| **Before tagging**| whoever pushes the tag                 | what must be applied first, in order, and what to check after |

`release_notes/v0.8.0.md` predates the sections (it is the v0.8.0 tag message, backfilled); the
file after it is the reference shape.

## 1. Find the range

```sh
git fetch --tags
git describe --tags --abbrev=0 --match 'v*' origin/main   # the last thing prod got
git log --oneline <tag>..origin/main
```

The range is always tag to `origin/main`, since the tag ships `main`, not your branch.

## 2. Read the diff, not the log

Commit subjects describe how the work went: a fix inside the range for something introduced
inside the range never shipped, and a feature added then removed (an event, a route) is nothing.
Read what changed between the two trees:

```sh
git diff --stat <tag>..origin/main -- api/lib/routes api/lib/core api/lib/models api/lib/inputs \
  api/lib/mcp api/lib/oauth shared/heart_models/lib database/migrations
git diff <tag>..origin/main -- api/lib/routes/index.dart api/lib/core/app.dart   # routes added or gone
git diff <tag>..origin/main -- shared/heart_models/CHANGELOG.md                  # what the app's pull gets
git diff --name-only <tag>..origin/main -- database/migrations                   # what the deploy applies
git diff <tag>..origin/main -- infrastructure/app/environments/prod infrastructure/app/stacks infrastructure/global infrastructure/dns
```

Where a change landed tells you its reader:

- `api/lib/routes/**`, `api/lib/core/*router*`, `api/lib/inputs/**`, `toMap` in `api/lib/models/**`,
  `api/lib/core/handler.dart` (status codes, error `code`s) — **contracts**. Every one goes in
  Compatibility, classified.
- `/me`, `/mcp`, `/oauth`, `api/lib/mcp/tools.dart` — also **Developers**.
- `shared/heart_models/lib/**` — Compatibility, by its CHANGELOG version range.
- `database/migrations/**` — Before tagging (the API deploy applies them). In Compatibility only
  if a response changes because of it.
- `infrastructure/**` — Before tagging, when prod or global changed. A gateway setting that
  changes a status code (a throttle, a gateway response) is also a contract.
- `site/**` — the site deploys from `main` on its own; mention it only when the release depends on
  a page being live (the OAuth consent page, the issuer metadata).
- tests, docs, CI, `.claude/**`, style-only commits — nowhere.

## 3. Write the sections

### Compatibility

The CLAUDE.md compatibility note, as a table: every contract change since the last tag, one row
each, classified as one of:

- **additive** — a new route, optional field or key, vocabulary value, package member;
- **widening** — the server accepts more than before;
- **tightening** — the server accepts less; say why no installed build sends what is now refused;
- **a phase of a named plan** — a breaking change; link its plan (the `breaking-change` skill).

A breaking change outside a plan is not a row; it stops the release. Then state the oldest app
version served correctly, what older builds lose, and whether `MIN_APP_VERSION` moves (it never
moves as a side effect).

Database-only changes (a column no response carries) are one row marked "database only", so the
next reader doesn't have to re-check.

### Developers

Only what a person on the token, MCP or OAuth surfaces would notice, in their words: routes and
their purpose, MCP tool names, limits and the codes they return, auth changes. Link
`https://heart-of.me/developers.html` and the design docs on `main` for detail. No internal
names (no Dart symbols, no table names). Empty when nothing changed for them: say so in one line.

### Before tagging

An ordered checklist with a box per step, written so it can be followed cold:

1. Terraform applies the release depends on, per stack and account (global, prod, dns), and the
   order between them. Mark the ones already done with the date.
2. Migrations the deploy will apply, by filename.
3. Anything the deploy does after the code lands (the `db.schedule` message for pg_cron jobs).
4. Anything that is broken between an apply and the tag. Example: a new Lambda carries the
   Terraform placeholder until the deploy, so its surface is down until the tag.
5. After the deploy: the checks that prove it worked, as commands or log lines.

## 4. Ship it

1. Commit `release_notes/v<version>.md` to a branch, open a PR, merge. The notes are reviewed
   like code. The user's call on wording wins.
2. Tag the merge, with the file as the message. `--cleanup=verbatim` keeps the lines starting
   with `#`, which git would otherwise strip as comments, title and headings included:

   ```sh
   git tag -a v<version> --cleanup=verbatim -F release_notes/v<version>.md origin/main
   git push origin v<version>
   ```

   Tags and prod are the user's: draft, never push a tag unasked.
3. `deploy-api-prod.yml` deploys, then creates the GitHub release from the same file (title from
   its first line). A missing file fails that job loudly. It doesn't undo the deploy.
4. Walk the *after the deploy* checks, and record anything that went differently in the file
   on `main`. The GitHub release can be edited to match.

## Rules

- **Versions.** Minor for a release with new surface, patch for fixes only. The API's pubspec
  version is inert. `heart_models` versions are reported, never chosen here.
- **No session links, no local paths, no secrets** in the file. It is public on GitHub.
- **Real names only**: route paths, tool names and error codes exactly as the code spells them.
  Copy them from the diff, never from memory.
