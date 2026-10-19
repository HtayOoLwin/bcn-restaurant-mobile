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
  test('multi UOM creates separate cart lines', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    const bottle = MenuItemModel(
      itemCode: 'DRINK-001', itemName: 'Whisky',
      itemGroup: 'Drinks', uom: 'Bottle', rate: 60000,
      currency: 'MMK', isStockItem: true,
    );
    const glass = MenuItemModel(
      itemCode: 'DRINK-001', itemName: 'Whisky',
      itemGroup: 'Drinks', uom: 'Glass', rate: 13000,
      currency: 'MMK', isStockItem: true,
    );
    final cart = container.read(cartProvider.notifier);
    cart.add(bottle);
    cart.add(glass);
    cart.add(glass);
    expect(container.read(cartProvider).lines.length, 2);
    expect(container.read(cartProvider).grandTotal, 86000);
    cart.decrement('DRINK-001', uom: 'Glass');
    expect(container.read(cartProvider).grandTotal, 73000);
  });

}
