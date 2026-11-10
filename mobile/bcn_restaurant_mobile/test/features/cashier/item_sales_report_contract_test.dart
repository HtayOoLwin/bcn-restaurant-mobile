import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('item sales report loads the date-scoped cashier API', () {
    final repository = File(
      'lib/features/cashier/data/cashier_repository.dart',
    ).readAsStringSync();
    expect(repository, contains('getItemSalesReport'));
    expect(repository, contains("'action': 'ItemSalesReport'"));
    expect(repository, contains("'date': date"));
  });

  test('cashier links report and shows summary, detail, FOC and Parcel filters', () {
    final cashier = File(
      'lib/features/cashier/presentation/cashier_screen.dart',
    ).readAsStringSync();
    final report = File(
      'lib/features/cashier/presentation/cashier_item_sales_report_screen.dart',
    ).readAsStringSync();
    expect(cashier, contains('CashierItemSalesReportScreen('));
    expect(report, contains('Item Summary'));
    expect(report, contains('Sales Details'));
    expect(report, contains("'FOC'"));
    expect(report, contains("'Parcel'"));
    expect(report, contains('unlinked_qty'));
    expect(report, contains('getItemSalesReport'));
    expect(report, contains("labelText: 'Search Item'"));
    expect(report, contains("labelText: 'Kitchen Counter'"));
    expect(report, contains("'counter'"));
    expect(report, contains("'item_code'"));
  });
}
