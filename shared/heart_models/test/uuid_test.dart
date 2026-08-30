import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

void main() {
  group('isUuidV7', () {
    test('accepts a minted v7 and a fixed one, either case', () {
      expect(isUuidV7(uuidV7()), isTrue);
      expect(isUuidV7('0198c1a2-b3c4-7d5e-8f60-718293a4b5c6'), isTrue);
      expect(isUuidV7('0198C1A2-B3C4-7D5E-8F60-718293A4B5C6'), isTrue);
    });

    test('rejects other versions, Firebase-era ids, and garbage', () {
      expect(isUuidV7('0198c1a2-b3c4-4d5e-8f60-718293a4b5c6'), isFalse, reason: 'v4');
      expect(isUuidV7('0198c1a2-b3c4-7d5e-c f60-718293a4b5c6'.replaceAll(' ', '')), isFalse, reason: 'bad variant');
      expect(isUuidV7('2023-01-01T10-00-00'), isFalse, reason: 'sanitized timestamp');
      expect(isUuidV7('Bench Press (Barbell)'), isFalse);
      expect(isUuidV7(''), isFalse);
    });
  });
}
