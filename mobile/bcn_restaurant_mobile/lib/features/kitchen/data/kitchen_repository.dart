import '../../../core/network/api_client.dart';
import '../domain/kitchen_models.dart';

class KitchenRepository {
  const KitchenRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<KitchenOrdersResponse> getOrders({String? status}) async {
    final data = await _apiClient.getMethod(
      'bcn_restaurant.api.kitchen.get_orders',
      queryParameters: {
        if (status != null && status.isNotEmpty && status != 'All') 'status': status,
      },
    );
    return KitchenOrdersResponse.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<void> updateItemStatus({required String rowName, required String action}) async {
    await _apiClient.postMethod(
      'bcn_restaurant.api.kitchen.update_item_status',
      data: {'item_row_name': rowName, 'action': action},
    );
  }
}
