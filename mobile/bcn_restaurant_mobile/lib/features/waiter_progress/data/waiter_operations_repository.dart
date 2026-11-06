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

  Future<Map<String, dynamic>> requestBill(String salesOrder, {required bool printBill}) async {
    final data = await _apiClient.postMethod(
      'bcn_request_for_bill',
      data: {'sales_order': salesOrder, 'print_bill': printBill ? '1' : '0'},
    );
    return Map<String, dynamic>.from(data as Map);
  }

  Future<void> markReadyForPayment(String salesOrder) async {
    await _apiClient.postMethod('bcn_waiter_pay', data: {'sales_order': salesOrder});
  }

  Future<void> itemAction({
    required String rowName,
    required String action,
    int? cancelQty,
  }) async {
    if (action == 'Cancel') {
      if (cancelQty == null || cancelQty <= 0) {
        throw ArgumentError.value(cancelQty, 'cancelQty', 'Cancel quantity must be positive');
      }
      final response = await _apiClient.postMethod(
        'bcn_waiter_cancel_order_item',
        data: {'item_row_name': rowName, 'cancel_qty': cancelQty.toString()},
      );
      if (response is! Map || response['success'] != true) {
        throw StateError('Server did not confirm item cancellation.');
      }
      return;
    }

    if (action == 'Mark Served') {
      // Preserve the existing Ready screen workflow and its original API.
      await _apiClient.postMethod(
        'bcn_waiter_orders',
        data: {'item_row_name': rowName, 'action': 'Mark Served'},
      );
      return;
    }

    throw ArgumentError.value(action, 'action', 'Unsupported item action');
  }

  Future<void> serveWholeOrder(String orderName) async {
    await _apiClient.postMethod(
      'bcn_waiter_orders',
      data: {'order_name': orderName, 'action': 'Serve Whole Order'},
    );
  }
}
