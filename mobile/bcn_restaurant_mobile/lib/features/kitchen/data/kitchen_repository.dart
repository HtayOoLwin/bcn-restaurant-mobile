import '../../../core/network/api_client.dart';
import '../domain/kitchen_models.dart';

class KitchenRepository {
  const KitchenRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<KitchenOrdersResponse> getOrders({String? status}) async {
    final data = await _apiClient.getMethod('bcn_kitchen_orders');
    final printData = await _apiClient.getMethod('bcn_kitchen_print');
    final snapshot = KitchenPrintSnapshot.fromJson(
      Map<String, dynamic>.from(printData as Map),
    );
    final response = KitchenOrdersResponse.fromJson(
      Map<String, dynamic>.from(data as Map),
    ).withPrintSnapshot(snapshot);

    if (status == null || status.isEmpty || status == 'All') {
      return response;
    }

    final filteredOrders = response.orders
        .map(
          (order) => KitchenOrder(
            name: order.name,
            customer: order.customer,
            session: order.session,
            creation: order.creation,
            preparationSummary: order.preparationSummary,
            items: order.items.where((item) {
              if (status == 'Preparing') {
                return item.preparationStatus == 'Preparing' || item.preparationStatus == 'Accepted';
              }
              return item.preparationStatus == status;
            }).toList(),
          ),
        )
        .where((order) => order.items.isNotEmpty)
        .toList();

    return KitchenOrdersResponse(
      orders: filteredOrders,
      allowedCounters: response.allowedCounters,
      counterSettings: response.counterSettings,
    );
  }

  Future<void> updateItemStatus({required String rowName, required String action}) async {
    await _apiClient.postMethod(
      'bcn_kitchen_orders',
      data: {'item_row_name': rowName, 'action': action},
    );
  }

  Future<void> recordPrint({
    required String orderName,
    required String counterName,
    required List<String> rowNames,
  }) async {
    await _apiClient.postMethod(
      'bcn_kitchen_print',
      data: {
        'action': 'Record Print',
        'order_name': orderName,
        'counter_name': counterName,
        'row_names': rowNames.join(','),
      },
    );
  }
}
