import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

void main() {
  group(
    'User Class Tests',
    () {
      test(
        'Constructor initializes all fields correctly',
        () {
          final user = User(
            displayName: 'John Doe',
            email: 'johndoe@example.com',
            avatar: 'https://example.com/avatar.jpg',
            id: 'user123',
            createdAt: DateTime.parse('2025-01-01T12:00:00Z'),
          );

          expect(user.displayName, 'John Doe');
          expect(user.email, 'johndoe@example.com');
          expect(user.remoteAvatar, 'https://example.com/avatar.jpg');
          expect(user.id, 'user123');
          expect(user.createdAt, DateTime.parse('2025-01-01T12:00:00Z'));
        },
      );

      test(
        'toMap returns correct map representation',
        () {
          final user = User(
            displayName: 'John Doe',
            email: 'johndoe@example.com',
            avatar: 'https://example.com/avatar.jpg',
            id: 'user123',
            createdAt: DateTime.parse('2025-01-01T12:00:00Z'),
          );

          final map = user.toMap();
          expect(
            map,
            {
              'displayName': 'John Doe',
              'email': 'johndoe@example.com',
              'avatar': 'https://example.com/avatar.jpg',
              'id': 'user123',
              'createdAt': '2025-01-01T12:00:00.000Z',
            },
          );
        },
      );

      test(
        'copyWith creates a new User with updated fields',
        () {
          final user = User(
            displayName: 'John Doe',
            email: 'johndoe@example.com',
            avatar: 'https://example.com/avatar.jpg',
            id: 'user123',
            createdAt: DateTime.parse('2025-01-01T12:00:00Z'),
          );

          final updatedUser = user.copyWith(displayName: 'Jane Doe', email: 'janedoe@example.com');

          expect(updatedUser.displayName, 'Jane Doe');
          expect(updatedUser.email, 'janedoe@example.com');
          expect(updatedUser.remoteAvatar, 'https://example.com/avatar.jpg');
          expect(updatedUser.id, 'user123');
          expect(updatedUser.createdAt, DateTime.parse('2025-01-01T12:00:00Z'));
        },
      );

      test(
        'copyWith keeps original fields when no arguments are passed',
        () {
          final user = User(
            displayName: 'John Doe',
            email: 'johndoe@example.com',
            avatar: 'https://example.com/avatar.jpg',
            id: 'user123',
            createdAt: DateTime.parse('2025-01-01T12:00:00Z'),
          );

          final updatedUser = user.copyWith();

          expect(updatedUser.displayName, 'John Doe');
          expect(updatedUser.email, 'johndoe@example.com');
          expect(updatedUser.remoteAvatar, 'https://example.com/avatar.jpg');
          expect(updatedUser.id, 'user123');
          expect(updatedUser.createdAt, DateTime.parse('2025-01-01T12:00:00Z'));
        },
      );

      test(
        'Handles null fields correctly',
        () {
          final user = User(
            id: 'user123',
          );

          expect(user.displayName, null);
          expect(user.email, null);
          expect(user.remoteAvatar, null);
          expect(user.id, 'user123');
          expect(user.createdAt, null);
        },
      );
    },
  );
}
