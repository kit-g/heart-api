-- import_id became opaque: the source prefix survives for targeted cleanup
-- ('strong:%'), but the rest is now a sha256-derived token instead of raw
-- '<date>#<workout name>' — a dedup key ends up in URLs and logs, and its
-- old shape leaked user content and invited parsing. Comment-only change;
-- the column and its partial unique index are untouched.

COMMENT ON COLUMN workouts.import_id IS
    'Deterministic opaque identity for bulk-imported workouts (''<source>:<16 hex of sha256 over the source row>''); unique per user, NULL for app-created workouts';
