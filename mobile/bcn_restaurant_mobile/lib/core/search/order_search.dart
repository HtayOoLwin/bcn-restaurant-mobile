bool matchesOrderSearch({
  required String queryText,
  required String tableName,
  required Iterable<String> orderNumbers,
  Iterable<String> searchTerms = const [],
}) {
  final query = queryText.trim().toLowerCase();
  if (query.isEmpty) return true;

  if (tableName.toLowerCase().contains(query)) return true;
  for (final orderNumber in orderNumbers) {
    if (orderNumber.toLowerCase().contains(query)) return true;
  }
  for (final searchTerm in searchTerms) {
    if (searchTerm.toLowerCase().contains(query)) return true;
  }
  return false;
}
