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

  Future<CashierPaymentResult> paySplit({
    required String salesOrder,
    required List<CashierPaymentTender> payments,
  }) async {
    final data = await _apiClient.postMethod(
      'bcn_cashier_billing',
      data: {
        'action': 'Pay',
        'sales_order': salesOrder,
        'payments': jsonEncode(
          payments
              .map(
                (tender) => {
                  'mode_of_payment': tender.modeOfPayment,
                  'amount': tender.amount,
                },
              )
              .toList(),
        ),
      },
    );
    return CashierPaymentResult.fromJson(
      Map<String, dynamic>.from(data as Map),
    );
  }
}
