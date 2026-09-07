import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('repository pays by sales order and removes invoice compatibility paths', () {
    final source = File(
      'lib/features/cashier/data/cashier_repository.dart',
    ).readAsStringSync();

    expect(source, contains("'bcn_cashier_billing'"));
    expect(source, contains('required String salesOrder'));
    expect(source, contains("'action': 'Pay'"));
    expect(source, contains("'sales_order': salesOrder"));
    expect(source, contains("'payments': jsonEncode("));
    expect(source, isNot(contains('invoiceName')));
    expect(source, isNot(contains("'invoice_name'")));
    expect(source, isNot(contains('recordBillPrint')));
  });

  test('paySplit returns the dedicated cashier payment result', () {
    final source = File(
      'lib/features/cashier/data/cashier_repository.dart',
    ).readAsStringSync();

    expect(source, contains('Future<CashierPaymentResult> paySplit'));
    expect(source, contains('CashierPaymentResult.fromJson'));
  });
}
