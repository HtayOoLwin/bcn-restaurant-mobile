import 'dart:convert';

import '../../../core/network/api_client.dart';
import '../domain/cashier_models.dart';

class CashierRepository {
  const CashierRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<CashierBillingResponse> getBilling() async {
    final data = await _apiClient.getMethod('bcn_cashier_billing');
    return CashierBillingResponse.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<CashierBillingResponse> recordBillPrint({
    required String invoiceName,
  }) async {
    final data = await _apiClient.postMethod(
      'bcn_cashier_billing',
      data: {
        'action': 'Record Print',
        'invoice_name': invoiceName,
      },
    );
    return CashierBillingResponse.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<CashierBillingResponse> paySplit({
    required String invoiceName,
    required List<CashierPaymentTender> payments,
  }) async {
    final data = await _apiClient.postMethod(
      'bcn_cashier_billing',
      data: {
        'action': 'Pay',
        'invoice_name': invoiceName,
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
    return CashierBillingResponse.fromJson(Map<String, dynamic>.from(data as Map));
  }

  // Kept for compatibility with older callers while split payment is rolled out.
  Future<CashierBillingResponse> pay({
    required String invoiceName,
    required String modeOfPayment,
    required double receivedAmount,
  }) async {
    final data = await _apiClient.postMethod(
      'bcn_cashier_billing',
      data: {
        'action': 'Pay',
        'invoice_name': invoiceName,
        'mode_of_payment': modeOfPayment,
        'received_amount': receivedAmount,
      },
    );
    return CashierBillingResponse.fromJson(Map<String, dynamic>.from(data as Map));
  }
}
