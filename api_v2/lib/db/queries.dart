part of 'db.dart';

extension on String {
  Sql toSql() => Sql.named(this);
}

final _updateProfile = '''
INSERT INTO profiles (id, email, username, updated_at)
VALUES (@id, @email, @username, now())
ON CONFLICT (id) 
DO UPDATE 
SET 
username = EXCLUDED.username, 
email = EXCLUDED.email, 
updated_at = now();
''';
