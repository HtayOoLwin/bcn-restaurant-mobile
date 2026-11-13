import 'dart:convert';

import '../../../core/network/api_client.dart';
import '../domain/cashier_models.dart';

class CashierRepository {
  const CashierRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<CashierBillingResponse> getBilling() async {
    final data = await _apiClient.getMethod('bcn_cashier_billing');
    return CashierBillingResponse.fromJson(
      Map<String, dynamic>.from(data as Map),
    );
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

  Future<Map<String, dynamic>> getItemSalesReport(String date) async {
    final data = await _apiClient.getMethod(
      'bcn_cashier_billing',
      queryParameters: {'action': 'ItemSalesReport', 'date': date},
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
