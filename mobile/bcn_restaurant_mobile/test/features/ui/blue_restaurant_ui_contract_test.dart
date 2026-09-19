import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  test('app uses the muted blue restaurant theme', () {
    final source = _read('lib/app.dart');

    expect(source, contains('0xFF1E5E96'));
    expect(source, contains('0xFFF4F7FB'));
    expect(source, isNot(contains('Colors.deepOrange')));
  });

  test('waiter tables use blue navigation and soft table cards', () {
    final source = _read(
      'lib/features/waiter/presentation/waiter_tables_screen.dart',
    );

    expect(source, contains('NavigationBar('));
    expect(source, contains("label: 'Tables'"));
    expect(source, contains("label: 'Orders'"));
    expect(source, contains("label: 'Settings'"));
    expect(source, contains("Text('Tables'"));
    expect(source, contains('Icons.table_restaurant_outlined'));
    expect(source, contains('Border.all('));
  });

  test('menu uses modern item cards and a blue cart action', () {
    final source = _read(
      'lib/features/menu/presentation/menu_screen.dart',
    );

    expect(source, contains('class _MenuItemCard'));
    expect(source, contains('item.itemGroup'));
    expect(source, contains("'View Cart'"));
    expect(source, contains('Icons.shopping_cart_outlined'));
    expect(source, contains('BorderRadius.circular(18)'));
  });

  test('cart uses polished item cards, notes, and a total panel', () {
    final source = _read(
      'lib/features/cart/presentation/cart_screen.dart',
    );

    expect(source, contains('class _CartLineCard'));
    expect(source, contains("labelText: 'Kitchen note'"));
    expect(source, contains("'Order Note (Optional)'"));
    expect(source, contains("'Place Order'"));
    expect(source, contains('cart.grandTotal'));
  });
}
