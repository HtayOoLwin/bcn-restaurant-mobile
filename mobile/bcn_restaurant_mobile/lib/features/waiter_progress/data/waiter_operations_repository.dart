import '../../../core/network/api_client.dart';
import '../domain/waiter_operation_models.dart';

class WaiterOperationsRepository {
  const WaiterOperationsRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<WaiterProgressResponse> getProgress() async {
    final data = await _apiClient.getMethod('bcn_restaurant.api.waiter.get_order_progress');
    return WaiterProgressResponse.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<WaiterReadyResponse> getReadyOrders() async {
    final data = await _apiClient.getMethod('bcn_restaurant.api.waiter.get_ready_orders');
    return WaiterReadyResponse.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<void> itemAction({required String rowName, required String action}) async {
    await _apiClient.postMethod(
      'bcn_restaurant.api.waiter.item_action',
      data: {'item_row_name': rowName, 'action': action},
    );
  }

  Future<void> serveWholeOrder(String orderName) async {
    await _apiClient.postMethod(
      'bcn_restaurant.api.waiter.serve_whole_order',
      data: {'order_name': orderName},
    );
  }
}
