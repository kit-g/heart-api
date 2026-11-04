import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

import 'wire.dart';

void main() {
  final at = DateTime.utc(2026, 11, 1, 9, 30);

  group('keys', () {
    final row = {
      'id': 'd1',
      'user_id': 'u1',
      'identity_key': 'i',
      'signing_key': 's',
      'fallback_key': 'f',
      'signature': 'sig',
      'vouched_by': 'd0',
      'created_at': at,
      'key_id': 'k1',
      'key': 'one-time',
    };

    test('CryptoDevices round-trips', () {
      expectRoundTrip(CryptoDevices([CryptoDevice.fromRow(row)]), CryptoDevices.fromJson);
    });

    test('CryptoDevices reads what a claim answers, from the rows the API reads', () {
      final read = CryptoDevices.fromJson(
        wire(
          CryptoDevices([
            CryptoDevice.fromRow(row),
            CryptoDevice.fromRow({
              ...row,
              'id': 'd2',
              'signature': null,
              'vouched_by': null,
              'key_id': null,
              'key': null,
            }),
          ]),
        ),
      );
      expect(read.devices.map((device) => device.id), ['d1', 'd2']);
      expect(read.devices.first.oneTimeKey, 'one-time');
      expect(read.devices.last.oneTimeKey, isNull);
      expect(read.devices.first.createdAt, at);
    });

    final item = QueuedItem.fromRow({
      'id': 'q1',
      'recipient_device_id': 'd1',
      'sender_device_id': 'd2',
      'kind': 'key',
      'content': 'sealed',
      'created_at': at,
    });

    test('QueuedItems round-trips', () => expectRoundTrip(QueuedItems([item]), QueuedItems.fromJson));

    test('QueuedItems reads the queue the API sends, a kind it does not know too', () {
      final read = QueuedItems.fromJson({
        'items': [
          {
            'id': 'q1',
            'recipientDeviceId': 'd1',
            'kind': 'something_new',
            'content': 'sealed',
            'createdAt': '2026-11-01T09:30:00.000Z',
          },
        ],
      });
      expect(read.items.single.kind, 'something_new');
      expect(read.items.single.senderDeviceId, isNull);
      expect(read.items.single.createdAt, at);
    });

    test('OneTimeKeyCount round-trips', () => expectRoundTrip(const OneTimeKeyCount(12), OneTimeKeyCount.fromJson));

    test('OneTimeKeyCount reads the API body', () => expect(OneTimeKeyCount.fromJson({'count': 0}).count, 0));
  });
}
