---
name: breaking-change
description: Assess and plan any change to something an installed app already sends or reads — a response field, a body key, a route, a query param, a status code or error code, an enum value, a jsonb blob the client reads, a CDN content shape, a heart_models signature. Use before writing code whenever a change removes, renames, retypes or re-means one of those, tightens what the server accepts, or raises the minimal app version. Triggers: "remove the field", "rename X to Y", "change the response", "drop the route", "change the status code", "tighten validation", "remove the enum value", "is this breaking", "migration plan", "bump the major", "force an upgrade", "raise the minimal version".
---

# Changing what an installed app depends on

Heart's first store releases — mobile **1.13** against API
**v0.9.0** (October 2026) — are the versions that get promoted. Every
build that reaches a phone stays installed for months, and a shipped app can't
be patched. From that release on, the API, the CDN content and `heart_models`
are read by builds we no longer control. Until then client and server shipped
together and a change was a change; now anything an installed build sends or
reads is a contract, and the question before any edit to one is: *which
installed build touches this, and what does it do with the change?*

## Additive is the default, and is safe

- A new route; a new optional field in a response; a new optional key accepted
  in a body (absent keeps the stored value — heart-api#84's shape).
- A new value of an existing vocabulary — a category, set type, goal metric,
  chart type, target, cadence, movement or health word. Safe from 2.11.0 on,
  because that release reads an unknown value tolerantly and carries it
  untouched (`docs/2026-10-05.tolerant-reads.md`). Builds older than that
  (1.10, 1.11) break on a new value; heart-api#125 accepted that loss once, for
  the weighted categories, and it is not to be repeated as a habit.
- A new `heart_models` public member: minor bump, changelog, same commit
  (CLAUDE.md, *Package versioning*).
- A column, table, index or function the client never sees.
- A new error `code` on a new failure. Existing codes keep their meaning.

If the change can be made additive, make it additive. Add beside, never
replace: a new field next to the old one, both accepted on write; a new route
rather than a changed one; a new `code` rather than a changed one. The old
one is retired later, through the plan below — or never, if it costs nothing.

## What is breaking

- Removing or renaming a response field, a body key, a query param, a route.
- Changing a field's type, unit, nullability or meaning (a name that becomes
  an id; kilograms that become pounds; a timestamp that becomes a date).
- Tightening validation so a body an installed build sends is now a 400.
- Removing or renaming a vocabulary value the app *sends* — the server's
  `fromString` rejects it as a 400, and the app has no way to learn the new
  word. (Adding one is additive; see above.)
- Changing a status code or an error `code` the app branches on.
- Changing the inside of a jsonb blob the client reads verbatim
  (`exercises.movement`, `goals.stages`, `profiles.settings`), or a key in
  the CDN library file.
- Changing or removing a `heart_models` public signature: a major, and the
  app pulls `main`, so it breaks the app's build the moment it lands.
- Raising the minimal app version: every build below it gets a 426 on every
  request (`api/lib/middleware/version.dart`, `minimalAppVersion` in
  `api/lib/globals/config.dart`). A forced upgrade for every user on an old
  build — the bluntest instrument here.

## The procedure

1. **Name what reads it.** Which app versions send or read the thing, and
   through which path (a `heart_models` `fromJson`, a hand-built body in the
   app's `heart_api` package, the local store). `x-app-version` arrives on
   every request, so the question "does anyone still send the old shape" has
   an answer in the logs; use it rather than guessing.

2. **Try the additive path first.** Most breaking changes have one; the cost
   is carrying the old shape for a while. Write that down as the chosen
   option before concluding it isn't.

3. **If it must break, the plan comes before the code**, on the ticket, in
   phases that each ship on their own:
   - *Server, additive.* Emit both shapes; accept both on write. Nothing
     installed notices.
   - *Package and app.* `heart_models` gains the new shape (minor; the old
     member is `@Deprecated`, not removed). The app moves to it and ships.
   - *Adoption.* Wait until the old shape's traffic is gone or below what you
     are willing to break — measured by `x-app-version`, or a stated
     deadline when measuring isn't worth it. State the number or the date in
     the plan.
   - *Retire.* Remove the old shape on the server; a `heart_models` major
     removes the deprecated member, coordinated with the app pin in the same
     window. Each removal is its own PR with the plan linked.
   - *Or a new API version instead of dual paths.* The API is served at `/v1`,
     an API Gateway stage on the function (`infrastructure/app/stacks/api`).
     A change too wide to carry as two shapes in one handler gets a `/v2`
     stage on a Lambda alias pinned to a published version, while `/v1` keeps
     serving installed builds from the version they were built against. The
     first use is infrastructure work (publish versions, an alias per stage,
     a second stage and base-path mapping); the plan says which route the
     retirement takes and when `/v1`'s traffic lets it go dark.
   - *Minimal version*, only if the plan says so: raising it is a product
     decision, announced in the app before it bites, never a shortcut for a
     schema change. The 426 body is the whole of what an old build sees.

4. **Two tickets, one plan.** The server side here, the app side in
   `heart-of-yours`, each linking the other and the design doc that records
   the plan (`docs/YYYY-MM-DD.slug.md`). Cross-repo tickets are requests, not
   instructions (CLAUDE.md); the plan's *phases and their order* are the hard
   constraint, with the reason — a build in the field — stated.

5. **Review asks the question.** Every PR touching a route, a model, a blob
   or a vocabulary answers it in its description: additive, or which phase
   of which plan. The `review-handoff` skill has a row for it.

## Every release

Compatibility is planned per release, not discovered per PR. Before a prod tag
(`v*`), the release carries a short compatibility note — in the tag's PR or
the release notes — that lists every contract change since the previous tag
and classifies it: additive, or phase *n* of a named plan. Along with it, the
oldest app version the release still serves correctly, and whether the
minimal app version moves. A release that can't fill that note in isn't
understood well enough to ship. The same note is where "1.10 and 1.11 lose
the catalog with this tag" gets written down, as heart-api#125 did, rather
than found out from a support thread.

## Not this skill

- A build that was never released, or a shape nobody in the field sends —
  no shims, no version branches. Speculative compatibility is still a finding
  (`docs/style.md`).
- Server-only models in `api/lib/models`, SQL, internal services: change
  freely, as before.
- The device-only health rule is a different rule and overrides this one
  (CLAUDE.md).
