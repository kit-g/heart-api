import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

void main() {
  group('OrderedCursor', () {
    test('serializes as <order>:<id>', () {
      expect(const OrderedCursor(order: 3, id: 't-9').toString(), '3:t-9');
    });

    test('round-trips its own wire form', () {
      const original = OrderedCursor(order: 12, id: '0198a0b1-0000-7000-8000-000000000001');
      final parsed = OrderedCursor.tryParse(original.toString())!;

      expect(parsed.order, original.order);
      expect(parsed.id, original.id);
    });

    test('a negative order survives the round trip', () {
      // order_index is a plain INTEGER with no non-negative constraint, so a
      // client that pins something to the top with -1 must still be pageable.
      final parsed = OrderedCursor.tryParse('-1:t-1')!;
      expect(parsed.order, -1);
      expect(parsed.id, 't-1');
    });

    test('an id containing colons is kept whole', () {
      final parsed = OrderedCursor.tryParse('0:a:b:c')!;
      expect(parsed.order, 0);
      expect(parsed.id, 'a:b:c');
    });

    test('absent is null, not an error', () {
      expect(OrderedCursor.tryParse(null), isNull);
    });

    for (final malformed in ['', 'nonsense', ':t-1', '3:', 'x:t-1', '3']) {
      test('rejects the malformed cursor "$malformed"', () {
        expect(OrderedCursor.tryParse(malformed), isNull);
      });
    }
  });

  group('Page', () {
    test('empty is exhausted', () {
      expect(Page.empty.items, isEmpty);
      expect(Page.empty.hasMore, isFalse);
    });

    test('iterates its items', () {
      const page = Page(items: [1, 2, 3], hasMore: true);
      expect(page.toList(), [1, 2, 3]);
      expect(page.hasMore, isTrue);
    });
  });
}
