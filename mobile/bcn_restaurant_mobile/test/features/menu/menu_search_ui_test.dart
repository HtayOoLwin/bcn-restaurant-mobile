import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File(
    'lib/features/menu/presentation/menu_screen.dart',
  ).readAsStringSync();

  test('menu screen exposes a searchable item field with clear action', () {
    expect(source, contains("String _searchQuery = '';"));
    expect(source, contains('final _searchController = TextEditingController();'));
    expect(source, contains("hintText: 'Search menu items'"));
    expect(source, contains('prefixIcon: const Icon(Icons.search)'));
    expect(source, contains("setState(() => _searchQuery = '');"));
    expect(source, contains('_searchController.dispose();'));
  });

  test('menu search matches item name and code inside selected category', () {
    expect(source, contains('final normalizedQuery = _searchQuery.trim().toLowerCase();'));
    expect(source, contains('item.itemName.toLowerCase().contains(normalizedQuery)'));
    expect(source, contains('item.itemCode.toLowerCase().contains(normalizedQuery)'));
    expect(source, contains('matchesCategory && matchesSearch'));
  });
}
