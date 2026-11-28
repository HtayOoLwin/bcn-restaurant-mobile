import 'dart:convert';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../domain/cashier_models.dart';

class CashierRepository {
  const CashierRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<CashierBillingResponse> getBilling() async {
    Map<String, dynamic> data;
    try {
      data = Map<String, dynamic>.from(await _apiClient.getMethod('bcn_cashier_billing') as Map);
    } on ApiException catch (error) {
      if (error.statusCode != null) rethrow;
      data = {'bills': [], 'modes': [], '_offline_cached': true};
    }
    final cached = data['_offline_cached'] == true;
    final bills = (data['bills'] as List? ?? []).map((row) => Map<String, dynamic>.from(row as Map)).toList();
    for (final bill in bills) {
      if (cached) bill['_local_preview'] = true;
    }
    final pending = await _apiClient.pendingOrders();
    for (final entry in pending.entries) {
      try {
        final record = jsonDecode(entry.value) as Map;
        final payload = record['payload'] as Map;
        final customer = payload['customer']?.toString() ?? '';
        final session = payload['session']?.toString() ?? '';
        if (customer.isEmpty) continue;
        final key = 'LOCAL:$customer:$session';
        final index = bills.indexWhere((b) => b['customer'] == customer &&
          (b['sales_order'] == key || (session.isNotEmpty && b['sales_order'] == session)));
        final Map<String, dynamic> bill;
        if (index >= 0) {
          bill = bills[index];
        } else {
          bill = {'sales_order': key, 'customer': customer, 'customer_name': customer,
            'grand_total': 0, 'net_total': 0, 'currency': 'MMK', 'items': [], 'taxes': []};
          bills.add(bill);
        }
        final raw = record['display_items'] ?? payload['items'];
        final additions = (raw is String ? jsonDecode(raw) : raw) as List;
        final items = (bill['items'] as List? ?? []).map((i) => Map<String, dynamic>.from(i as Map)).toList();
        for (final value in additions) {
          final item = Map<String, dynamic>.from(value as Map);
          items.add({...item, 'item_name': item['item_name'] ?? item['item_code'],
            'description': 'Offline addition · pending sync', 'custom_foc': item['foc']});
        }
        final amount = (record['estimated_total'] as num?) ?? 0;
        bill['items'] = items;
        bill['grand_total'] = ((bill['grand_total'] as num?) ?? 0) + amount;
        bill['net_total'] = ((bill['net_total'] as num?) ?? 0) + amount;
        bill['_local_preview'] = true;
        bill['offline_cash_eligible'] = false;
        bill['restaurant_status'] = 'Pending Sync';
      } catch (_) {
        // Keep malformed local records available for review.
      }
    }
    final payments = await _apiClient.pendingPayments();
    for (final raw in payments.values) {
      final payment = jsonDecode(raw) as Map;
      for (final bill in bills.where((b) => b['customer'] == payment['customer'])) {
        bill['_cash_recorded'] = true;
        bill['offline_cash_eligible'] = false;
        bill['restaurant_status'] = (payment['credit_customer']?.toString() ?? '').isNotEmpty
            ? 'Credit recorded · pending sync' : 'Cash received · pending sync';
      }
    }
    return CashierBillingResponse.fromJson({...data, 'bills': bills});
  }

  Future<List<Map<String, dynamic>>> searchCreditCustomers(String query) async {
    final data = await _apiClient.getMethod(
      'bcn_cashier_billing',
      queryParameters: {'action': 'Customers', 'search': query},
    );
    final rows = (data as Map)['customers'] as List? ?? const [];
    return rows.map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }

  Future<Map<String, dynamic>> getDailyReport(String date) async {
    final data = await _apiClient.getMethod(
      'bcn_cashier_billing',
      queryParameters: {'action': 'DailyReport', 'date': date},
    );
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> getSalesSummaryByItem({
    required String date,
    String salesCounter = '',
    String itemGroup = '',
  }) async {
    final data = await _apiClient.getMethod(
      'bcn_mobile_sales_summary_by_item',
      queryParameters: {
        'from_date': date,
        'to_date': date,
        'options': 'All',
        if (salesCounter.isNotEmpty) 'sales_counter': salesCounter,
        if (itemGroup.isNotEmpty) 'item_group': itemGroup,
      },
    );
    return Map<String, dynamic>.from(data as Map);
  }

  /// Freeze check-out and final room charges once, before Pay/Credit dialogs.
  Future<Map<String, dynamic>> startCheckout(String salesOrder) async {
    final data = await _apiClient.postMethod(
      'bcn_cashier_billing',
      data: {'action': 'StartCheckout', 'sales_order': salesOrder},
    );
    final result = Map<String, dynamic>.from(data as Map);
    if (result['room_charges_locked'] != true) {
      throw StateError('Server did not confirm room charges checkout lock.');
    }
    return result;
  }

  Future<Map<String, dynamic>> preparePayment(
    String salesOrder, {
    String? creditCustomer,
  }) async {
    final requestData = <String, dynamic>{
      'action': 'Pay',
      'sales_order': salesOrder,
    };
    if (creditCustomer != null) {
      requestData['credit_customer'] = creditCustomer;
    }
    final data = await _apiClient.postMethod(
      'bcn_cashier_billing',
      data: requestData,
    );
    return Map<String, dynamic>.from(data as Map);
  }

  Future<CashierPaymentResult> confirmPayment({
    required String salesOrder,
    required List<CashierPaymentTender> payments,
    double discountAmount = 0,
    String paymentType = 'Paid',
    double creditAmount = 0,
    String creditRemark = '',
  }) async {
    final data = await _apiClient.postMethod(
      'bcn_cashier_billing',
      data: {
        'action': 'ConfirmPayment',
        'sales_order': salesOrder,
        'discount_amount': discountAmount,
        'payment_type': paymentType,
        'credit_amount': creditAmount,
        'credit_remark': creditRemark,
        'payments': jsonEncode(
          payments.map((t) => {
            'mode_of_payment': t.modeOfPayment,
            'amount': t.amount,
          }).toList(),
        ),
      },
    );
    return CashierPaymentResult.fromJson(
      Map<String, dynamic>.from(data as Map),
    );
  }

  @Deprecated('Use preparePayment and confirmPayment in two separate steps')
  Future<CashierPaymentResult> paySplit({
    required String salesOrder,
    required List<CashierPaymentTender> payments,
  }) => confirmPayment(salesOrder: salesOrder, payments: payments);
}
