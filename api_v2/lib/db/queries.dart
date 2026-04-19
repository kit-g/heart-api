part of 'db.dart';

extension on String {
  Sql toSql() => Sql.named(this);
}

final _updateProfile = '''
INSERT INTO profiles (id, email, username, avatar_url, updated_at)
VALUES (@id, @email, @username, @avatar, now())
ON CONFLICT (id) 
DO UPDATE 
SET 
username = EXCLUDED.username, 
email = EXCLUDED.email, 
avatar_url = EXCLUDED.avatar_url, 
updated_at = now();
''';

final _createConnection = '''
WITH target_exists AS (
  SELECT 1 FROM profiles WHERE id = @targetId
),
inserted AS (
  INSERT INTO connections (initiator_id, target_id, initiator_role, target_role, domain)
  SELECT @initiatorId, @targetId, @initiatorRole, @targetRole, @domain
  WHERE exists(SELECT 1 FROM target_exists)
  ON CONFLICT (initiator_id, target_id, domain) DO NOTHING
  RETURNING target_id, initiator_role AS "role", domain, status, created_at
)
SELECT target_id, "role", domain, status, created_at FROM inserted
UNION ALL
SELECT
  CASE WHEN initiator_id = @initiatorId THEN target_id ELSE initiator_id END AS target_id,
  CASE WHEN initiator_id = @initiatorId THEN initiator_role ELSE target_role END AS role,
  domain, 
  status, 
  created_at
FROM connections
WHERE domain = @domain
  AND exists(SELECT 1 FROM target_exists)
  AND NOT exists(SELECT 1 FROM inserted)
  AND (
    (initiator_id = @initiatorId AND target_id = @targetId)
    OR 
    (initiator_id = @targetId AND target_id = @initiatorId)
  )
''';

final _listConnections = '''
SELECT
  target_id,
  initiator_role AS role,
  domain,
  status,
  created_at
FROM connections
WHERE initiator_id = @userId
  AND (@role::text IS NULL OR initiator_role = @role)
UNION ALL
SELECT initiator_id AS target_id, target_role AS role, domain, status, created_at
FROM connections
WHERE target_id = @userId
  AND (@role::text IS NULL OR target_role = @role)
ORDER BY created_at DESC
''';

final _getConnection = '''
SELECT
  CASE WHEN initiator_id = @userId THEN target_id ELSE initiator_id END AS target_id,
  CASE WHEN initiator_id = @userId THEN initiator_role ELSE target_role END AS role,
  domain, status, created_at
FROM connections
WHERE domain = @domain
  AND (
    (initiator_id = @userId AND target_id = @targetId AND initiator_role = @role)
    OR (initiator_id = @targetId AND target_id = @userId AND target_role = @role)
  )
''';

final _deleteConnection = '''
DELETE FROM connections
WHERE (initiator_id, target_id, domain) IN (
  (@initiatorId, @targetId, @domain),
  (@targetId, @initiatorId, @domain)
)
''';

final _updateConnectionStatus = '''
UPDATE connections SET status = @newStatus
WHERE (initiator_id, target_id, domain) IN (
  (@initiatorId, @targetId, @domain),
  (@targetId, @initiatorId, @domain)
)
''';
