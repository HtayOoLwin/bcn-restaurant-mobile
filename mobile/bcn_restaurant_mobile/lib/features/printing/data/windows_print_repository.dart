import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/cashier_bill_print_result.dart';

abstract interface class WindowsPrintGateway {
  Future<CashierBillPrintResult> requestCashierBill({
    required String salesOrder,
    required String requestId,
  });
}

class WindowsPrintRepository implements WindowsPrintGateway {
  const WindowsPrintRepository(this._apiClient);

  static const _requestCashierBillMethod = 'bcn_cashier_print_bill';

  final ApiClient _apiClient;

  @override
  Future<CashierBillPrintResult> requestCashierBill({
    required String salesOrder,
    required String requestId,
  }) async {
    final resolvedSalesOrder = salesOrder.trim();
    final resolvedRequestId = requestId.trim();

    if (resolvedSalesOrder.isEmpty) {
      throw const FormatException('salesOrder is required for cashier print.');
    }
    if (resolvedRequestId.isEmpty) {
      throw const FormatException('requestId is required for cashier print.');
    }

    final data = await _apiClient.postMethod(
      _requestCashierBillMethod,
      data: {
        'sales_order': resolvedSalesOrder,
        'request_id': resolvedRequestId,
      },
    );
    return CashierBillPrintResult.fromJson(_responseMap(data));
  }
}

final windowsPrintRepositoryProvider = Provider<WindowsPrintGateway>(
  (ref) => WindowsPrintRepository(ref.watch(apiClientProvider)),
);

Map<String, dynamic> _responseMap(Object? data) {
  if (data is! Map) {
    throw const FormatException('Print API returned an invalid response.');
  }
  try {
    return Map<String, dynamic>.from(data);
  } on TypeError {
    throw const FormatException('Print API returned an invalid response.');
  }
}
