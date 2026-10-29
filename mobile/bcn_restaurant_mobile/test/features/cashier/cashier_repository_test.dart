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

  test('credit payment submits payment type and keeps tender list available', () {
    final source = File(
      'lib/features/cashier/data/cashier_repository.dart',
    ).readAsStringSync();

    expect(source, contains("String paymentType = 'Paid'"));
    expect(source, contains("'payment_type': paymentType"));
    expect(source, contains("'discount_amount': discountAmount"));
    expect(source, contains("'payments': jsonEncode("));
  });

  test('cashier screen shows a credit option and outstanding summary', () {
    final source = File(
      'lib/features/cashier/presentation/cashier_screen.dart',
    ).readAsStringSync();

    expect(source, contains('const creditPaymentType = \'Credit\''));
    expect(source, contains('label: const Text(\'Credit\')'));
    expect(source, contains("label: 'Credit Outstanding'"));
    expect(source, contains('payments: tenders,'));
    expect(source, contains('label: Text('));
    expect(source, contains("'Confirm Credit'"));
  });
}
