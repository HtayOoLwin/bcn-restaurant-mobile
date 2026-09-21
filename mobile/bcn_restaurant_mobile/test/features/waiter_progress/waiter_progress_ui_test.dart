import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const screenPath =
      'lib/features/waiter_progress/presentation/waiter_progress_screen.dart';

  late String source;

  setUpAll(() {
    source = File(screenPath).readAsStringSync();
  });

  test('progress screen refreshes orders when opened', () {
    expect(source, contains('WidgetsBinding.instance.addPostFrameCallback'));
    expect(source, contains('ref.invalidate(waiterProgressProvider);'));
  });

  test('progress card hides kitchen status summary labels', () {
    expect(source, isNot(contains('Text(order.preparationSummary)')));
    expect(source, isNot(contains("'New \${order.newQty.g}'")));
    expect(source, isNot(contains("'Preparing \${order.preparingQty.g}'")));
    expect(source, isNot(contains("'Ready \${order.readyQty.g}'")));
    expect(source, isNot(contains("'Served \${order.servedQty.g}'")));
  });

  test('progress card starts collapsed and table header toggles item details', () {
    expect(source, contains('class _ProgressCard extends StatefulWidget'));
    expect(source, contains('bool _expanded = false;'));
    expect(source, contains('setState(() => _expanded = !_expanded)'));
    expect(source, contains('if (_expanded) ...['));
  });

  test('collapsed header shows table name sales order and bill action', () {
    final cardStart = source.indexOf('class _ProgressCard');
    final headerStart = source.indexOf('Row(', cardStart);
    final expandedStart = source.indexOf('if (_expanded) ...[', headerStart);
    final header = source.substring(headerStart, expandedStart);

    expect(header, contains('widget.order.customer'));
    expect(header, contains('widget.order.name'));
    expect(header, contains('Request for Bill'));
    expect(header, isNot(contains('widget.order.items')));
  });

  test('table header shows expand and collapse arrow cues', () {
    expect(source, contains('Icons.expand_more'));
    expect(source, contains('Icons.expand_less'));
    expect(source, contains('_expanded ? Icons.expand_less : Icons.expand_more'));
  });

  test('item rows appear only inside expanded content', () {
    final expandedStart = source.indexOf('if (_expanded) ...[');
    final itemList = source.indexOf('...widget.order.items.map(', expandedStart);

    expect(expandedStart, greaterThanOrEqualTo(0));
    expect(itemList, greaterThan(expandedStart));
  });

  test('expanded item rows mirror cashier quantity x item style without money totals', () {
    final expandedStart = source.indexOf('if (_expanded) ...[');
    final cardEnd = source.indexOf('\n  }\n}\n\nextension on double', expandedStart);
    final expandedContent = source.substring(expandedStart, cardEnd);

    expect(
      expandedContent,
      contains("'\${item.qty.g} × \${item.itemName}'"),
    );
    expect(expandedContent, isNot(contains('item.uom')));
    expect(expandedContent, isNot(contains('item.kitchenCounter')));
    expect(expandedContent, isNot(contains('item.kitchenNote')));
    expect(expandedContent, isNot(contains('formatMoney(')));
    expect(expandedContent, isNot(contains("'Subtotal'")));
    expect(expandedContent, isNot(contains("'Grand Total'")));
  });
}
