import 'dart:convert';

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
      // Fetch current Customer.customer_name after an ERPNext rename/edit.
      // A unique query prevents intermediate HTTP caches from returning an
      // older takeaway table list.
      queryParameters: {
        'customer_group': customerGroup,
        '_refresh': DateTime.now().millisecondsSinceEpoch,
      },
    );
    final response = TablesResponse.fromJson(Map<String, dynamic>.from(data as Map));
    final pending = await _apiClient.pendingOrders();
    final customers = <String>{};
    for (final raw in pending.values) {
      try {
        final record = jsonDecode(raw) as Map;
        final payload = record['payload'] as Map;
        customers.add(payload['customer']?.toString() ?? '');
      } catch (_) {}
    }
    final paidCustomers = <String>{};
    for (final raw in (await _apiClient.pendingPayments()).values) {
      final record = jsonDecode(raw) as Map;
      paidCustomers.add(record['customer']?.toString() ?? '');
    }
    return TablesResponse(serviceType: response.serviceType, companyName: response.companyName,
      customerGroup: response.customerGroup, customerGroups: response.customerGroups,
      tables: response.tables.map((t) => paidCustomers.contains(t.customer)
        ? RestaurantTableModel(customer: t.customer, customerName: t.customerName,
            customerGroup: t.customerGroup, isOpen: true, session: t.session,
            sessionStatus: 'Billing', waiter: t.waiter, openedAt: t.openedAt, hasPendingOrders: true)
        : customers.contains(t.customer)
        ? RestaurantTableModel(customer: t.customer, customerName: t.customerName,
            customerGroup: t.customerGroup, isOpen: true, session: t.session,
            sessionStatus: t.isOpen ? t.sessionStatus : 'Occupied',
            waiter: t.waiter, openedAt: t.openedAt, hasPendingOrders: true)
        : t).toList());
  }
}
