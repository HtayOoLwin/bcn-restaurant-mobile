import 'dart:convert';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../domain/waiter_operation_models.dart';

class WaiterOperationsRepository {
  const WaiterOperationsRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<WaiterProgressResponse> getProgress() async {
    Map<String, dynamic> data;
    try {
      data = Map<String, dynamic>.from(await _apiClient.getMethod('bcn_waiter_order_progress') as Map);
    } on ApiException catch (error) {
      if (error.statusCode != null) rethrow;
      final pending = await _apiClient.pendingOrders();
      if (pending.isEmpty) rethrow;
      data = {'orders': [], '_offline_cached': true};
    }
    final records = await _apiClient.pendingOrders();
    final rows = (data['orders'] as List? ?? []).map((r) => Map<String, dynamic>.from(r as Map)).toList();
    final cached = data['_offline_cached'] == true;
    for (final row in rows) {
      if (cached) {
        row['_offline_cached'] = true;
        row['_local_preview'] = true;
      }
    }
    for (final entry in records.entries) {
      try {
        final record = jsonDecode(entry.value) as Map;
        final payload = record['payload'] as Map;
        final customer = payload['customer']?.toString() ?? '';
        final session = payload['session']?.toString() ?? '';
        if (customer.isEmpty) continue;
        final localKey = 'LOCAL:$customer:$session';
        final index = rows.indexWhere((row) =>
          row['customer'] == customer &&
          (session.isNotEmpty && row['name'] == session || row['name'] == localKey));
        final Map<String, dynamic> row;
        if (index < 0) {
          row = {'name': localKey, 'customer': customer, 'customer_name': customer,
            'items': <Map<String, dynamic>>[], 'currency': 'MMK', 'grand_total': 0.0,
            'net_total': 0.0, 'preparation_summary': 'Pending sync'};
          rows.add(row);
        } else {
          row = rows[index];
        }
        final raw = record['display_items'] ?? payload['items'];
        final incoming = (raw is String ? jsonDecode(raw) : raw) as List;
        final items = (row['items'] as List? ?? []).map((i) => Map<String, dynamic>.from(i as Map)).toList();
        for (final value in incoming) {
          final item = value as Map;
          final qty = (item['qty'] as num?)?.toDouble() ?? 0;
          final code = item['item_code']?.toString() ?? '';
          final foc = item['foc'] == 1;
          final parcel = item['parcel'] == 1;
          bool flag(dynamic value) => value == 1 || value == true || value == '1';
          final match = items.indexWhere((i) => code.isNotEmpty && i['item_code'] == code &&
            i['uom'] == item['uom'] && flag(i['custom_foc']) == foc &&
            flag(i['custom_parcel']) == parcel &&
            (i['kitchen_note'] ?? '') == (item['kitchen_note'] ?? ''));
          if (match >= 0) {
            final target = items[match];
            target['_online_qty'] ??= target['qty'];
            target['_offline_qty'] = ((target['_offline_qty'] as num?) ?? 0) + qty;
            target['qty'] = ((target['qty'] as num?) ?? 0) + qty;
            target['amount'] = ((target['amount'] as num?) ?? 0) + ((item['amount'] as num?) ?? 0);
            target['status'] = 'Pending sync';
          } else {
            items.add({'row_name': 'LOCAL:${entry.key}:${items.length}', 'item_code': code,
              'item_name': item['item_name'] ?? code, 'qty': qty, 'uom': item['uom'],
              'custom_foc': foc, 'custom_parcel': parcel, 'kitchen_note': item['kitchen_note'],
              'rate': (item['rate'] as num?) ?? 0, 'amount': (item['amount'] as num?) ?? 0,
              '_online_qty': 0, '_offline_qty': qty, 'status': 'Pending sync'});
          }
        }
        final amount = (record['estimated_total'] as num?)?.toDouble() ?? 0;
        row['items'] = items;
        row['_local_preview'] = true;
        row['_offline_cached'] = cached;
        row['_pending_amount'] = ((row['_pending_amount'] as num?) ?? 0) + amount;
        row['grand_total'] = ((row['grand_total'] as num?) ?? 0) + amount;
      } catch (_) {
        // Unreadable records remain in the separate pending-orders list.
      }
    }
    for (final row in rows.where((r) => r['_local_preview'] == true)) {
      row['items'] = (row['items'] as List? ?? []).map((item) => {
        ...Map<String, dynamic>.from(item as Map), 'can_cancel': false, 'cancelable_qty': 0,
      }).toList();
    }
    return WaiterProgressResponse.fromJson({'orders': rows});
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
    bool confirmPrintedCancel = false,
  }) async {
    if (action == 'Cancel') {
      if (cancelQty == null || cancelQty <= 0) {
        throw ArgumentError.value(cancelQty, 'cancelQty', 'Cancel quantity must be positive');
      }
      final response = await _apiClient.postMethod(
        'bcn_waiter_cancel_order_item',
        data: {
          'item_row_name': rowName,
          'cancel_qty': cancelQty.toString(),
          'confirm_printed_cancel': confirmPrintedCancel ? '1' : '0',
        },
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
