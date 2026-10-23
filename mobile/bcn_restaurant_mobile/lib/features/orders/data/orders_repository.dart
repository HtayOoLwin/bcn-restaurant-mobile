import 'dart:convert';

import '../../../core/network/api_client.dart';
import '../../cart/domain/cart_controller.dart';
import '../domain/order_result.dart';

class OrdersRepository {
  const OrdersRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<OrderResult> createOrder(CartState cart) async {
    final customer = cart.customer;
    if (customer == null || customer.isEmpty) {
      throw StateError('Customer/table is missing from the cart.');
    }
    if (cart.lines.isEmpty) {
      throw StateError('Cart is empty.');
    }

    final clientOrderId = cart.clientOrderId;
    if (clientOrderId == null || clientOrderId.isEmpty) {
      throw StateError('Client Order ID is missing from the cart.');
    }

    final payload = <String, dynamic>{
      'customer': customer,
      'client_order_id': clientOrderId,
      'items': jsonEncode(
        cart.lines
            .map(
              (line) => {
                'item_code': line.item.itemCode,
                'qty': line.qty,
                'uom': line.item.uom,
                if (line.kitchenNote.isNotEmpty)
                  'kitchen_note': line.kitchenNote,
              },
            )
            .toList(),
      ),
    };
    if (cart.roomChargeItemCode != null) {
      payload['room_charge_item'] = cart.roomChargeItemCode;
    }
    if (cart.session != null && cart.session!.isNotEmpty) {
      payload['session'] = cart.session;
    }
    if (cart.remarks.isNotEmpty) {
      payload['remarks'] = cart.remarks;
    }

    final data = await _apiClient.postMethod(
      'bcn_mobile_create_order',
      data: payload,
    );
    if (data is! Map) {
      throw StateError('Invalid response from Create Order API');
    }
    var body = Map<String, dynamic>.from(data);
    // Handle nested Frappe API Server Script return envelopes.
    for (var i = 0; i < 5; i++) {
      if ((body['sales_order']?.toString().trim() ?? '').isNotEmpty) {
        break;
      }
      final nested = body['message'] ?? body['data'] ?? body['result'];
      if (nested is! Map) break;
      body = Map<String, dynamic>.from(nested);
    }
    final name = body['sales_order']?.toString().trim() ?? '';
    if (name.isEmpty) {
      final fields = body.keys.join(', ');
      throw StateError(
        'Create Order API response missing sales_order (fields: $fields). '
        'Check ERPNext Sales Orders for this table before retrying.',
      );
    }
    return OrderResult.fromJson(body);
  }
}
