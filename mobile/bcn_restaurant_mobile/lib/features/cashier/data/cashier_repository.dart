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

  Future<Map<String, dynamic>> preparePayment(String salesOrder) async {
    final data = await _apiClient.postMethod(
      'bcn_cashier_billing',
      data: {'action': 'Pay', 'sales_order': salesOrder},
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
