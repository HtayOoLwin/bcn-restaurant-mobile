import '../../../core/network/api_client.dart';
import '../domain/waiter_operation_models.dart';

class WaiterOperationsRepository {
  const WaiterOperationsRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<WaiterProgressResponse> getProgress() async {
    final data = await _apiClient.getMethod('bcn_waiter_order_progress');
    return WaiterProgressResponse.fromJson(
      Map<String, dynamic>.from(data as Map),
    );
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
