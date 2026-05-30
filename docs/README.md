# docs

Long-form notes, design explorations, decision records.

## Naming

`YYYY-MM-DD.short-name.md` — date-prefixed for chronological sort, short kebab-case slug for the topic. Examples:

- `2026-05-12.postgrest-reads.md`
- `2026-06-01.mobile-deep-links.md`

Things that should live here:
- Decision records and "we explored X, here's where we landed."
- Architecture sketches that don't have a natural home in a service README.
- Tickets/explorations we plan to revisit but aren't acting on yet.

Things that should NOT live here:
- Code-adjacent docs (those go in `<service>/README.md` next to the code).
- Active runbooks (those go in `infrastructure/` or service READMEs).
- Memory entries (those are Claude's `.claude/projects/.../memory/`).
