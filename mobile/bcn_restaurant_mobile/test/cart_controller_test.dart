import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bcn_restaurant_mobile/features/cart/domain/cart_controller.dart';
import 'package:bcn_restaurant_mobile/features/menu/domain/menu_models.dart';

void main() {
  test('cart add increment decrement and total', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    const item = MenuItemModel(
      itemCode: 'FOOD-001',
      itemName: 'Chicken Fried Rice',
      itemGroup: 'Food Menu',
      uom: 'Plate',
      rate: 8000,
      currency: 'MMK',
      isStockItem: false,
    );

    final controller = container.read(cartProvider.notifier);
    controller.setOrderContext(customer: 'Table 01', session: 'RTS-2026-00001');
    final firstClientOrderId = container.read(cartProvider).clientOrderId;
    controller.add(item);
    controller.add(item);

    expect(container.read(cartProvider).totalQty, 2);
    expect(container.read(cartProvider).grandTotal, 16000);
    expect(container.read(cartProvider).clientOrderId, firstClientOrderId);
    expect(firstClientOrderId, isNotNull);

    controller.decrement('FOOD-001');
    expect(container.read(cartProvider).totalQty, 1);
    expect(container.read(cartProvider).grandTotal, 8000);
  });
}
