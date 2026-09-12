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

  test('table grid chooses a responsive fixed column count', () {
    expect(source, contains('LayoutBuilder('));
    expect(source, contains('waiterTableColumnCount('));
    expect(source, contains('crossAxisCount:'));
  });
}
