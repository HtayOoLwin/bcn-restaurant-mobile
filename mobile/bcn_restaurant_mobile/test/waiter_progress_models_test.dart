import 'package:bcn_restaurant_mobile/features/waiter_progress/domain/waiter_operation_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('waiter progress honors explicit non-cancellable New line', () {
    final response = WaiterProgressResponse.fromJson({
      'orders': [
        {
          'name': 'SAL-ORD-1',
          'customer': 'Table 01',
          'preparation_summary': 'New',
          'items': [
            {
              'row_name': 'ROW-1',
              'item_name': 'Chicken Fried Rice',
              'qty': 1,
              'status': 'New',
              'can_cancel': false,
            },
          ],
        },
      ],
    });

    expect(response.orders.single.items.single.canCancel, isFalse);
    expect(response.orders.single.items.single.status, 'New');
  });

  test('waiter progress parses an authorized cancellable New line', () {
    final item = WaiterProgressItem.fromJson({
      'row_name': 'ROW-1',
      'item_name': 'Chicken Fried Rice',
      'qty': 1,
      'status': 'New',
      'can_cancel': true,
    });

    expect(item.canCancel, isTrue);
  });

  test('ready response parses whole-order capability', () {
    final response = WaiterReadyResponse.fromJson({
      'orders': [
        {
          'name': 'SAL-ORD-1',
          'customer': 'Table 01',
          'can_serve_whole': true,
          'items': [],
        },
      ],
    });
    expect(response.orders.single.canServeWhole, isTrue);
  });
}
