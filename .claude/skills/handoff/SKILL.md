---
name: handoff
description: Hand a backend-first feature off to the Flutter app (heart-of-yours). Use after a feature lands on main that the app must consume, or when reporting progress on a backend ticket. Produces the four linked artifacts — design doc, heart_models wire models, frontend ticket, backend-ticket report — so an agent in the app repo can implement its side without ever seeing this repo. Triggers: "hand this off", "report back to the ticket", "write the frontend ticket", "the app needs to consume this".
---

# Handing a backend feature off to the app

Heart is two repos that ship together: this one (backend) and
[`heart-of-yours`](https://github.com/kit-g/heart-of-yours) (Flutter app). The app — and any
agent working in it — can read exactly three things from here: the `shared/heart_models` package it
pulls from git `main` (code + `CHANGELOG.md`), GitHub issues, and public repo files via links. It
cannot see `api/lib`, so a contract that lives only in route handlers and model classes here does
not exist on that side. The backend usually lands features first; this procedure is how the
headstart crosses the gap.

The first worked example is bulk CSV import: backend ticket
[heart-api#39](https://github.com/kit-g/heart-api/issues/39), commit `0c23ecd`. Use its report
comment as the tone/format reference for step 5.

## The four artifacts

Every handoff produces all four, cross-linked. Skipping one leaves a future agent (here or there)
without its anchor.

1. **Design doc** — `docs/YYYY-MM-DD.<slug>.md`. The durable reference: tickets go stale after
   closing, the doc tracks the code. House style is `docs/2026-08-02.connections.md`: written from
   the code as it stands ("nothing here is a proposal unless it says so"), data model, API surface
   with `jsonc` request/response examples, behavioral semantics, a Gaps section. Naming rules are in
   `docs/README.md`.
2. **Wire models in `shared/heart_models`** — only the shapes the app must *parse* (response
   models; request bodies that are JSON). A raw-body or query-param-only request needs no model.
   Additive only, minor bump + `CHANGELOG.md` entry in the same commit (see CLAUDE.md's versioning
   rules); the CHANGELOG entry links the frontend ticket, because that file is what the app side
   reads to learn what a pull brings in.
3. **Frontend ticket** in `heart-of-yours` — the agent brief. This is the primary instrument:
   assume the implementing agent reads *only this ticket*, so the contract goes inline, with links
   as backup, not as the mechanism.
4. **Report on the backend ticket** — scope-vs-delivered, what remains, links to the other three.

## Steps

1. **Reconstruct what shipped.** `git log`/`git show` the relevant commits; read the backend ticket;
   classify each scope bullet as delivered / partial / not done. Don't report from memory of the
   session — report from the diff.

2. **Write or update the design doc.** If one exists for the domain, update it (they are living
   documents); otherwise create it. Include everything an implementer or future study needs:
   schema, endpoint surface, real examples, error cases, the Gaps section for known holes.

3. **Ship the wire models.** Add `fromJson` models to `heart_models` for anything the app parses.
   Semantics ("retry the whole file, it's idempotent") do not go in models — they go in the ticket
   and doc. Bump + CHANGELOG in the same commit, entry links the frontend ticket.

4. **Author the frontend ticket.** Structure:
   - **Contract** — verb + path + query params, auth, exact body format (be explicit about
     raw-body vs multipart vs JSON — this is the thing an agent guesses wrong), a *real* response
     example (from a test or live call, never invented), enumerated error cases with status codes.
   - **Behavioral semantics** — the part no schema carries. Cover at least: how the data actually
     arrives (in the response vs via normal sync afterwards), what the app must refetch or
     invalidate, idempotency/retry rules, payload ceilings (the API sits on Lambda behind API
     Gateway: ~6–10 MB hard request limit — state it so the client fails gracefully), and what a
     response *carries* that the app may want to surface (e.g. an import report has per-row
     detail) — as a fact about the data, not a screen to build.
   - **Required** — only when the change is mandatory or breaking for the app: a migration it
     must run before a pin moves, a field it must now send, data it would otherwise lose. State
     the consequence of skipping it. If nothing is required, say so in one line.
   - **What becomes possible** — the capabilities the change opens up, as capabilities: "sets
     carry a type the app can let users set", not "add a long-press to mark warm-ups". No UX
     prescriptions, no task lists, no candidate designs. See *Capabilities, not instructions*
     below.
   - **References** — backend ticket, design doc (full GitHub URL to the file on `main`), the
     landing commit, the `heart_models` version that carries the wire models.
   - Label `enhancement` and `agent-filed` (CLAUDE.md, *Tickets across the boundary*).

5. **Report back to the backend ticket.** Comment with: what landed (commit, migration, endpoint),
   scope checklist (✅ / ⚠️ partial / ❌ with one line of why), validation story, remaining work,
   links to the frontend ticket and design doc. Close the ticket only if nothing remains; otherwise
   leave it open with the remainder explicit.

6. **Cross-link check.** Backend issue ↔ frontend issue ↔ design doc ↔ CHANGELOG entry: each names
   the others. An artifact that nothing points to is one a future agent never finds.

## Rules

- **Capabilities, not instructions.** The backend never tells the app what to build. A handoff
  says what is *required* (the change is mandatory or breaking: a migration, a field that must be
  sent, data that would be lost) and what is *possible* (new fields, new endpoints, their limits).
  Everything else — which screens, what interaction, whether a feature is shown at all, opt-in or
  not — is the app's call, and UX is found by iterating, not specified up front. That applies to
  the ticket, the report and the design doc alike: no "App work" checklists, no suggested
  widgets, no "the app should". Product decisions already settled on the backend ticket can be
  linked, not restated as orders. Link generously instead: the design doc, the CHANGELOG, and
  the backend ticket's decisions give the app the full picture without directing it.

- **The floor is the store.** Since mobile 1.12 / `heart_models` 2.11.0, a change the app must
  make *before* a server deploy is safe is not a handoff note — it is a breaking change with a
  phased plan (`breaking-change` skill), and the *Required* section names the phase and its
  consequence. A handoff proper is additive: the app can take it whenever it likes.

- **No local paths or localhost URLs in any shared artifact** (tickets, docs, CHANGELOG, PR text).
  Repo-relative paths (`api/lib/models/imports.dart`) or full GitHub URLs only.
- **Examples are real.** Response bodies come from tests or a live call, never composed from
  reading the model code — invented examples encode your misreadings.
- **`heart_models` stays additive** — the app pulls `main`, so every merge is released instantly.
- **The ticket carries semantics; the package carries shapes; the doc carries both plus history.**
  Don't let any artifact try to do another's job. The `CHANGELOG` is where this slips: endpoint
  behaviour, a widened query filter, "the server never does X" guarantees are all doc material. The
  entry says what shapes a pull brings in, plus how the package itself treats them (what `fromJson`
  rejects), and links the ticket for the rest. Same rule downward — see *Comments stay in their own
  layer* in `docs/style.md`.

## Iterating on this skill

This file is the anchor for the procedure — edit it in the same PR as whatever changes it. Known
future upgrades:

- **OpenAPI generation** (`api/tool/generate_openapi.dart` PoC): blocked on responses being runtime
  `toMap()` shapes with no static declaration — see the "On generating an OpenAPI spec" section of
  `docs/2026-08-02.connections.md` for the convention fix (a declared route → input/output
  registry). When a committed `openapi.json` exists on `main`, step 4's Contract section shrinks to
  a link plus the behavioral-semantics prose, which no spec will ever carry.
- **Frontend label conventions** — currently defaults-only over there; revise step 4 when real
  conventions emerge.