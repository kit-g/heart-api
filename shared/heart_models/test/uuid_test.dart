import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

void main() {
  group(
    'timestampOfUuidV7',
    () {
      test(
        'recovers the mint instant of a v7 uuid',
        () {
          final before = DateTime.timestamp();
          final id = uuidV7();
          final after = DateTime.timestamp();

          final minted = timestampOfUuidV7(id);

          expect(minted, isNotNull);
          // v7 carries millisecond precision, so allow the window's edges.
          expect(minted!.isBefore(before.subtract(const Duration(milliseconds: 1))), isFalse);
          expect(minted.isAfter(after.add(const Duration(milliseconds: 1))), isFalse);
        },
      );

      test(
        'reads the leading 48 bits as milliseconds since the epoch',
        () {
          expect(
            timestampOfUuidV7('01950000-0000-7000-8000-000000000000'),
            equals(DateTime.fromMillisecondsSinceEpoch(0x019500000000, isUtc: true)),
          );
        },
      );

      test(
        'yields nothing for anything that is not a v7 uuid',
        () {
          // a Firebase-era timestamp id
          expect(timestampOfUuidV7('2025-01-21T12:00:00.000Z'), isNull);
          // a v4 uuid
          expect(timestampOfUuidV7('e58ed763-928c-4155-bee9-fdbaaadc15f3'), isNull);
          expect(timestampOfUuidV7(''), isNull);
          expect(timestampOfUuidV7('garbage'), isNull);
        },
      );
    },
  );
}
