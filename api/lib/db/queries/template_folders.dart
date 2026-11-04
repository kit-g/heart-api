part of '../db.dart';

const _listTemplateFolders = '''
SELECT
  f.id,
  f.name,
  f.order_index,
  f.created_at,
  count(t.id) AS template_count
FROM template_folders f
LEFT JOIN templates t ON t.folder_id = f.id
WHERE f.user_id = @userId
GROUP BY f.id
ORDER BY f.order_index, lower(f.name)
''';

/// Idempotent create for a folder, the replay's second resource
/// (heart-api#66): a client id the caller already owns, or a name (on
/// the case-insensitive index) the caller already has, resolves to that
/// existing folder with `created = false` — replacing the old `400 "you
/// already have a folder called..."`. An id owned by someone else matches
/// neither pre-check and falls through to the plain INSERT, tripping
/// `template_folders_pkey` — `403 id_taken` via `_rethrowForeignId`.
const _createTemplateFolder = '''
WITH
_by_id AS (
  SELECT id, name, order_index, created_at FROM template_folders
  WHERE id = @id::uuid AND user_id = @userId
),
_by_name AS (
  -- the real unique index (template_folders_user_name_idx) already keys on
  -- lower(name), so this can only ever match one row; LIMIT 1 documents that
  -- rather than relying on it silently
  SELECT id, name, order_index, created_at FROM template_folders
  WHERE user_id = @userId AND lower(name) = lower(@name)
  ORDER BY id
  LIMIT 1
),
_ins AS (
  INSERT INTO template_folders (id, user_id, name, order_index)
  SELECT coalesce(@id::uuid, uuidv7()), @userId, @name, @orderIndex
  WHERE NOT EXISTS (SELECT 1 FROM _by_id) AND NOT EXISTS (SELECT 1 FROM _by_name)
  RETURNING id, name, order_index, created_at
)
SELECT id, name, order_index, created_at, 0 AS template_count, true AS created FROM _ins
UNION ALL
SELECT id, name, order_index, created_at, 0 AS template_count, false AS created FROM _by_id
WHERE NOT EXISTS (SELECT 1 FROM _ins)
UNION ALL
SELECT id, name, order_index, created_at, 0 AS template_count, false AS created FROM _by_name
WHERE NOT EXISTS (SELECT 1 FROM _ins) AND NOT EXISTS (SELECT 1 FROM _by_id)
''';

/// Three outcomes, told apart without a second round trip: no rows (the folder
/// is not the caller's), one row with `name_taken` (the rename would collide),
/// one row with the folder (renamed).
const _updateTemplateFolder = '''
WITH
_target AS (
  SELECT id FROM template_folders
  WHERE id = @folderId::uuid AND user_id = @userId
),
_conflict AS (
  SELECT 1 FROM template_folders
  WHERE user_id = @userId
    AND lower(name) = lower(@name)
    AND id <> @folderId::uuid
),
_updated AS (
  UPDATE template_folders
  SET name = @name, order_index = @orderIndex
  WHERE id = (SELECT id FROM _target)
    AND NOT EXISTS (SELECT 1 FROM _conflict)
  RETURNING id, name, order_index, created_at
)
SELECT
  t.id,
  u.name,
  u.order_index,
  u.created_at,
  (SELECT count(*) FROM templates WHERE folder_id = t.id) AS template_count,
  EXISTS (SELECT 1 FROM _conflict) AS name_taken
FROM _target t
LEFT JOIN _updated u ON u.id = t.id
''';

/// The templates inside survive — `templates_folder_fk` is `ON DELETE SET NULL
/// (folder_id)`, so they come back unfiled rather than being destroyed.
const _deleteTemplateFolder = '''
DELETE FROM template_folders
WHERE id = @folderId::uuid AND user_id = @userId
RETURNING id
''';

/// Runs only when a folder assignment shared nothing, to tell the three causes
/// apart: an unknown folder, an unknown student, or a folder that is simply
/// empty. One row, always.
const _diagnoseEmptyFolderShare = '''
SELECT
  EXISTS (SELECT 1 FROM template_folders WHERE id = @folderId::uuid AND user_id = @coachId) AS folder_exists,
  EXISTS (SELECT 1 FROM profiles WHERE id = @studentId) AS student_exists
''';
