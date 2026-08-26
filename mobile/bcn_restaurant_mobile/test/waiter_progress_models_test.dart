import 'package:bcn_restaurant_mobile/features/waiter_progress/domain/waiter_operation_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('waiter progress parses cancellable New line', () {
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
              'can_cancel': true,
            }
          ],
        }
      ]
    });

    expect(response.orders.single.items.single.canCancel, isTrue);
    expect(response.orders.single.items.single.status, 'New');
  });

  test('ready response parses whole-order capability', () {
    final response = WaiterReadyResponse.fromJson({
      'orders': [
        {'name': 'SAL-ORD-1', 'customer': 'Table 01', 'can_serve_whole': true, 'items': []}
      ]
    });
    expect(response.orders.single.canServeWhole, isTrue);
  });
}
