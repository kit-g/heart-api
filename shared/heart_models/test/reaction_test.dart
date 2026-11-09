import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

import 'wire.dart';

void main() {
  final reaction = Reaction.fromRow({
    'id': '01900000-0000-7000-8000-000000000001',
    'author_id': 'friend',
    'author_name': 'Alex',
    'kind': 'cheer',
    'target_type': 'exercise_set',
    'target_id': '01900000-0000-7000-8000-000000000002',
    'created_at': DateTime.utc(2026, 11, 8),
  });

  test('Reaction round-trips, its target read from the row', () {
    expectRoundTrip(reaction, Reaction.fromJson);
    expect(reaction.targetType, CommentTarget.exerciseSet);
    expect(reaction.toMap()['targetType'], 'exercise_set');
  });

  test('Reactions round-trips, with its counts and the reader\'s own', () {
    expectRoundTrip(
      Reactions(reactions: [reaction], counts: {'cheer': 2}, mine: 'cheer', cursor: 'c'),
      Reactions.fromJson,
    );
  });

  test('a word this build does not know is carried, and a reaction it can\'t read leaves the rest', () {
    final read = Reactions.fromJson({
      'reactions': [
        {...wire(reaction), 'kind': 'fire'},
        {...wire(reaction), 'targetType': 'something_new'},
      ],
      'counts': {'fire': 1, 'cheer': 1},
    });
    expect(read.reactions.single.kind, 'fire');
    expect(read.counts, {'fire': 1, 'cheer': 1});
    expect(read.mine, isNull);
  });
}
