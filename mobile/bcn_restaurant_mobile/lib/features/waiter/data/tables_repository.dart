import '../../../core/network/api_client.dart';
import '../domain/table_models.dart';

class TablesRepository {
  const TablesRepository(this._apiClient);

  final ApiClient _apiClient;

  /// Reads only currently available destination tables.
  Future<List<RestaurantTableModel>> getTransferCandidates(
    String fromCustomer,
  ) async {
    final raw = await _apiClient.getMethod(
      'bcn_mobile_transfer_tables_search',
      queryParameters: {'from_customer': fromCustomer},
    );
    if (raw is! Map) {
      throw const FormatException('Invalid destination table response.');
    }
    final data = Map<String, dynamic>.from(raw);
    final rows = data['tables'];
    if (rows is! List) {
      throw const FormatException('Available tables list is missing.');
    }
    return rows.map((row) => RestaurantTableModel.fromJson(
      Map<String, dynamic>.from(row as Map),
    )).toList();
  }

  /// Transfers an existing Open Draft Sales Order without creating an order.
  Future<void> transferTable({
    required String salesOrder,
    required String fromCustomer,
    required String toCustomer,
  }) async {
    final raw = await _apiClient.postMethod(
      'bcn_mobile_transfer_table',
      data: {
        'sales_order': salesOrder,
        'from_customer': fromCustomer,
        'to_customer': toCustomer,
      },
    );
    if (raw is! Map || raw['success'] != true) {
      throw StateError(
        raw is Map
            ? (raw['message'] ?? 'Table transfer was not confirmed.').toString()
            : 'Invalid table transfer response.',
      );
    }
  }

  Future<TablesResponse> getTables(String customerGroup) async {
    final data = await _apiClient.getMethod(
      'bcn_mobile_tables',
      queryParameters: {'customer_group': customerGroup},
    );
    return TablesResponse.fromJson(Map<String, dynamic>.from(data as Map));
  }
}
