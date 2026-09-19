import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const screenPath =
      'lib/features/waiter/presentation/waiter_tables_screen.dart';

  late String source;

  setUpAll(() {
    source = File(screenPath).readAsStringSync();
  });

  test('service type selector uses horizontally scrollable chips', () {
    expect(source, contains('SingleChildScrollView('));
    expect(source, contains('scrollDirection: Axis.horizontal'));
    expect(source, contains('ChoiceChip('));
    expect(source, isNot(contains('SegmentedButton<String>')));
  });

  test('table cards do not render the sales order session number', () {
    expect(source, isNot(contains('table.session!')));
  });

  test('table grid gives phone cards enough vertical space', () {
    expect(source, contains('LayoutBuilder('));
    expect(source, contains('waiterTableColumnCount('));
    expect(source, contains('crossAxisCount:'));
    expect(source, contains('columns == 3 ? 0.88'));
  });

  test('table status colors fill the whole card', () {
    expect(source, contains('Color cardBackground;'));
    expect(source, contains('color: cardBackground'));
    expect(source, contains("case 'occupied':"));
    expect(source, contains("case 'billing':"));
    expect(source, contains("case 'available':"));
  });

  test('orders bottom navigation opens order progress', () {
    expect(source, contains("context.push('/waiter-progress')"));
    expect(source, contains("label: 'Orders'"));
  });
}
