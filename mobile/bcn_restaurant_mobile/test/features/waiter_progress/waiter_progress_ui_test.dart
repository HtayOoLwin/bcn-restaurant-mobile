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

  test('progress card starts collapsed and table name toggles item details', () {
    expect(source, contains('class _ProgressCard extends StatefulWidget'));
    expect(source, contains('bool _expanded = false;'));
    expect(source, contains('setState(() => _expanded = !_expanded)'));
    expect(source, contains('if (_expanded) ...['));
  });

  test('collapsed header contains table name and bill action only', () {
    final cardStart = source.indexOf('class _ProgressCard');
    final headerStart = source.indexOf('Row(', cardStart);
    final expandedStart = source.indexOf('if (_expanded) ...[', headerStart);
    final header = source.substring(headerStart, expandedStart);

    expect(header, contains('widget.order.customer'));
    expect(header, contains('Request for Bill'));
    expect(header, isNot(contains('widget.order.name')));
    expect(header, isNot(contains('widget.order.items')));
  });

  test('item rows appear only inside expanded content', () {
    final expandedStart = source.indexOf('if (_expanded) ...[');
    final itemList = source.indexOf('...widget.order.items.map(', expandedStart);

    expect(expandedStart, greaterThanOrEqualTo(0));
    expect(itemList, greaterThan(expandedStart));
  });

  test('item rows show quantity and counter without item preparation status', () {
    expect(source, isNot(contains('\${item.status}')));
    expect(source, contains('\${item.qty.g} \${item.uom}'));
    expect(source, contains('item.kitchenCounter'));
  });
}
