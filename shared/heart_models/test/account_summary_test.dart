import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

void main() {
  group('CollectionSummary', () {
    test('round-trips a populated collection', () {
      const summary = CollectionSummary(count: 412, latestId: '0198-workout');

      expect(summary.toMap(), {'count': 412, 'latestId': '0198-workout'});
      expect(CollectionSummary.fromJson(summary.toMap()).latestId, '0198-workout');
    });

    test('omits latestId rather than emitting null', () {
      expect(const CollectionSummary(count: 0).toMap(), {'count': 0});
      expect(CollectionSummary.fromJson({'count': 0}).latestId, isNull);
    });

    for (final json in <Map<String, dynamic>>[
      {},
      {'count': -1},
      {'count': '3'},
      {'count': 1, 'latestId': ''},
      {'count': 1, 'latestId': 7},
    ]) {
      test('throws on $json', () {
        expect(() => CollectionSummary.fromJson(json), throwsArgumentError);
      });
    }
  });

  group('AccountSummary', () {
    const summary = AccountSummary(
      collections: {
        ExportableCollection.workouts: CollectionSummary(count: 412, latestId: '0198-workout'),
        ExportableCollection.connections: CollectionSummary(count: 2),
      },
    );

    test('serializes collections under their wire keys', () {
      expect(summary.toMap(), {
        'collections': {
          'workouts': {'count': 412, 'latestId': '0198-workout'},
          'connections': {'count': 2},
        },
      });
    });

    test('round-trips through fromJson', () {
      final parsed = AccountSummary.fromJson(summary.toMap());

      expect(parsed[ExportableCollection.workouts].count, 412);
      expect(parsed[ExportableCollection.connections].latestId, isNull);
      expect(parsed.total, 414);
    });

    test('reads a collection the server omitted as zero', () {
      expect(summary[ExportableCollection.goals].count, 0);
      expect(summary[ExportableCollection.goals].latestId, isNull);
    });

    test('skips a collection this build has never heard of', () {
      // An app lagging a server that added a collection still parses the rest,
      // rather than failing the whole completeness check.
      final parsed = AccountSummary.fromJson({
        'collections': {
          'workouts': {'count': 1},
          'somethingAddedLater': {'count': 99},
        },
      });

      expect(parsed.collections.keys, [ExportableCollection.workouts]);
      expect(parsed.total, 1);
    });

    test('throws when the collections envelope is missing', () {
      expect(() => AccountSummary.fromJson(const {}), throwsArgumentError);
    });
  });

  group('ExportableCollection.tryParse', () {
    test('parses every known wire key', () {
      for (final collection in ExportableCollection.values) {
        expect(ExportableCollection.tryParse(collection.name), collection);
      }
    });

    for (final raw in ['', 'workout', 'custom_exercises', 'deviceTokens']) {
      test('returns null for "$raw"', () {
        expect(ExportableCollection.tryParse(raw), isNull);
      });
    }
  });
}
