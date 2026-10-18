# Synthetic Strong exports

These four files describe the same invented history: two workouts and five sets.
`bare` has neither notes nor rest timers; `notes` and `timers` enable one each;
`full` has both. Measurements, set types and RPE stay identical across all four.

The notes include commas, quotes and an embedded newline. Rest Timer rows must
set exercise preferences without becoming sets. The database suite checks the
stored values independently, then verifies that importing the variants in different
orders converges on the complete history and never removes richer information.

These fixtures always run in CI. Personal exports under `content/assets/exports/strong`
are an additional local check and are never copied into this directory.
