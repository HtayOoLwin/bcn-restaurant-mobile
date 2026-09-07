import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cashier screen uses Sales Order billing models after Task 6 refactor', () {
    final source = File(
      'lib/features/cashier/presentation/cashier_screen.dart',
    ).readAsStringSync();

    expect(source, contains('data.bills'));
    expect(source, contains('CashierBill'));
    expect(source, contains('salesOrder: bill.salesOrder'));
    expect(source, isNot(contains('data.invoices')));
    expect(source, isNot(contains('CashierInvoice')));
    expect(source, isNot(contains('invoiceName:')));
  });
}
