import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mobile printing exposes only request-idempotent cashier queue actions', () {
    final repository = File(
      'lib/features/printing/data/windows_print_repository.dart',
    ).readAsStringSync();
    final screen = File(
      'lib/features/printing/presentation/printer_settings_screen.dart',
    ).readAsStringSync();

    expect(repository, contains('Future<CashierBillPrintResult> requestCashierBill'));
    expect(repository, contains("'bcn_cashier_print_bill'"));
    expect(repository, isNot(contains('requestCashierBillLegacy')));
    expect(repository, isNot(contains('getStatus()')));
    expect(repository, isNot(contains('retryJob(')));
    expect(repository, isNot(contains('windowsPrintStatusProvider')));

    expect(screen, isNot(contains('windowsPrintStatusProvider')));
    expect(screen, isNot(contains('lastAcceptedPrintJobProvider')));
    expect(screen, isNot(contains('.retryJob(')));
    expect(screen, isNot(contains('requestCashierBillLegacy')));
    expect(
      screen,
      contains('Print and reprint bills from the Cashier screen.'),
    );
  });
}
