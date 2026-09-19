import '../../../core/network/api_client.dart';
import '../domain/waiter_operation_models.dart';

class WaiterOperationsRepository {
  const WaiterOperationsRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<WaiterProgressResponse> getProgress() async {
    try {
      final data = await _apiClient.getMethod('bcn_waiter_order_progress');
      final response = WaiterProgressResponse.fromJson(
        Map<String, dynamic>.from(data as Map),
      );
      if (response.orders.isNotEmpty) {
        return response;
      }
    } catch (_) {
      // The table API is already the source used by the waiter home screen.
      // Fall back to it when the dedicated progress endpoint is unavailable.
    }

    return _getProgressFromActiveTables();
  }

  Future<WaiterProgressResponse> _getProgressFromActiveTables() async {
    final firstData = await _apiClient.getMethod('bcn_mobile_tables');
    final firstPayload = Map<String, dynamic>.from(firstData as Map);

    final customerGroups = (firstPayload['customer_groups'] as List? ?? const [])
        .map((value) => value.toString())
        .where((value) => value.isNotEmpty)
        .toList();
    final firstGroup = firstPayload['customer_group']?.toString() ?? '';

    final ordersByName = <String, WaiterProgressOrder>{};

    void collect(Map<String, dynamic> payload) {
      final rows = payload['tables'] as List? ?? const [];
      for (final rawRow in rows) {
        final row = Map<String, dynamic>.from(rawRow as Map);
        if (row['is_open'] == true) {
          final session = row['session']?.toString() ?? '';
          final sessionStatus = row['session_status']?.toString() ?? '';
          if (session.isEmpty || sessionStatus.toLowerCase() == 'billing') {
            continue;
          }

          ordersByName[session] = WaiterProgressOrder(
            name: session,
            customer:
                row['customer_name']?.toString() ??
                row['customer']?.toString() ??
                '',
            preparationSummary: sessionStatus.isEmpty ? 'New' : sessionStatus,
            items: const [],
            newQty: 0,
            preparingQty: 0,
            readyQty: 0,
            servedQty: 0,
          );
        }
      }
    }

    collect(firstPayload);

    for (final group in customerGroups) {
      if (group == firstGroup) continue;

      final data = await _apiClient.getMethod(
        'bcn_mobile_tables',
        queryParameters: {'customer_group': group},
      );
      collect(Map<String, dynamic>.from(data as Map));
    }

    return WaiterProgressResponse(orders: ordersByName.values.toList());
  }

  Future<WaiterReadyResponse> getReadyOrders() async {
    final data = await _apiClient.getMethod('bcn_waiter_orders');
    return WaiterReadyResponse.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<Map<String, dynamic>> requestBill(String salesOrder) async {
    final data = await _apiClient.postMethod(
      'bcn_request_for_bill',
      data: {'sales_order': salesOrder},
    );
    return Map<String, dynamic>.from(data as Map);
  }

  Future<void> itemAction({
    required String rowName,
    required String action,
  }) async {
    await _apiClient.postMethod(
      'bcn_waiter_orders',
      data: {'item_row_name': rowName, 'action': action},
    );
  }

  Future<void> serveWholeOrder(String orderName) async {
    await _apiClient.postMethod(
      'bcn_waiter_orders',
      data: {'order_name': orderName, 'action': 'Serve Whole Order'},
    );
  }
}
