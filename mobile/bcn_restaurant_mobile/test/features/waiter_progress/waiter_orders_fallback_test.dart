import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File(
    'lib/features/waiter_progress/data/waiter_operations_repository.dart',
  ).readAsStringSync();

  test('order progress falls back to active table data', () {
    expect(source, contains("getMethod('bcn_waiter_order_progress')"));
    expect(source, contains("getMethod('bcn_mobile_tables'"));
    expect(source, contains("'customer_group': group"));
    expect(source, contains("row['is_open'] == true"));
    expect(source, contains("row['session']"));
    expect(source, contains("sessionStatus.toLowerCase() == 'billing'"));
  });
}
