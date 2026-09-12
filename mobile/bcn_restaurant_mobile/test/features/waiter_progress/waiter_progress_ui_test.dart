import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const screenPath =
      'lib/features/waiter_progress/presentation/waiter_progress_screen.dart';

  late String source;

  setUpAll(() {
    source = File(screenPath).readAsStringSync();
  });

  test('progress card hides kitchen status summary labels', () {
    expect(source, isNot(contains('Text(order.preparationSummary)')));
    expect(source, isNot(contains("'New \${order.newQty.g}'")));
    expect(source, isNot(contains("'Preparing \${order.preparingQty.g}'")));
    expect(source, isNot(contains("'Ready \${order.readyQty.g}'")));
    expect(source, isNot(contains("'Served \${order.servedQty.g}'")));
  });

  test('request for bill action is rendered in the table header before items', () {
    final cardStart = source.indexOf('class _ProgressCard');
    final tableName = source.indexOf('order.customer', cardStart);
    final requestButton = source.indexOf('FilledButton.icon(', tableName);
    final itemList = source.indexOf('...order.items.map(', tableName);

    expect(cardStart, greaterThanOrEqualTo(0));
    expect(tableName, greaterThan(cardStart));
    expect(requestButton, greaterThan(tableName));
    expect(itemList, greaterThan(requestButton));
  });

  test('item rows show quantity and counter without item preparation status', () {
    expect(source, isNot(contains('\${item.status}')));
    expect(source, contains('\${item.qty.g} \${item.uom}'));
    expect(source, contains('item.kitchenCounter'));
  });
}
