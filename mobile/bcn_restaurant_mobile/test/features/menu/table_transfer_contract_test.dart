import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('menu shows teal transfer action and preserves room charges', () {
    final source = File(
      'lib/features/menu/presentation/menu_screen.dart',
    ).readAsStringSync();

    expect(source, contains("Text('Table Transfer')"));
    expect(source, contains('Color(0xFF00A99A)'));
    expect(source, contains("Text('Room Charges')"));
    expect(source, contains('Color(0xFFED9418)'));
    expect(source, isNot(contains("'Select menu items'")));
  });

  test('transfer offers searchable empty destinations and confirmation', () {
    final source = File(
      'lib/features/menu/presentation/menu_screen.dart',
    ).readAsStringSync();

    expect(source, contains('getTransferCandidates(widget.customer)'));
    expect(source, contains('Search destination table...'));
    expect(source, contains('Available tables only'));
    expect(source, contains('Confirm Table Transfer'));
    expect(source, contains('transferTable('));
    expect(source, contains("context.go('/tables')"));
    expect(source, isNot(contains('Transfer History')));
  });

  test('transfer repository uses dedicated Frappe methods', () {
    final source = File(
      'lib/features/waiter/data/tables_repository.dart',
    ).readAsStringSync();

    expect(source, contains("'bcn_mobile_transfer_tables_search'"));
    expect(source, contains("'bcn_mobile_transfer_table'"));
    expect(source, contains("'sales_order': salesOrder"));
    expect(source, contains("'from_customer': fromCustomer"));
    expect(source, contains("'to_customer': toCustomer"));
  });
}
