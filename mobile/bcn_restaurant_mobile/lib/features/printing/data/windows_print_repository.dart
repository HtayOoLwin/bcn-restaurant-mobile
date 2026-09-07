import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/cashier_bill_print_result.dart';
import '../domain/windows_print_status.dart';

abstract interface class WindowsPrintGateway {
  Future<CashierBillPrintResult> requestCashierBill({
    required String salesOrder,
    required String requestId,
  });

  // Transitional compile surface for screens that are refactored in Task 8.
  // It deliberately performs no network request because cashier printing now
  // requires an explicit request id for idempotency.
  Future<PrintRequestResult> requestCashierBillLegacy(String salesOrder);

  // Transitional surface retained so the existing printer-settings screen
  // continues to compile until its legacy status UI is removed/refactored.
  Future<WindowsPrintStatus> getStatus();

  Future<void> retryJob(String jobId);
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

  @override
  Future<PrintRequestResult> requestCashierBillLegacy(String salesOrder) {
    throw UnsupportedError(
      'Cashier printing requires a request id. Use the cashier print action.',
    );
  }

  @override
  Future<WindowsPrintStatus> getStatus() {
    throw UnsupportedError(
      'Mobile Windows print status is unavailable in the polling queue flow.',
    );
  }

  @override
  Future<void> retryJob(String jobId) {
    throw UnsupportedError(
      'Automatic print-job retry is disabled. Reprint from the cashier bill.',
    );
  }
}

final windowsPrintRepositoryProvider = Provider<WindowsPrintGateway>(
  (ref) => WindowsPrintRepository(ref.watch(apiClientProvider)),
);

final windowsPrintStatusProvider =
    FutureProvider.autoDispose<WindowsPrintStatus>(
      (ref) => ref.watch(windowsPrintRepositoryProvider).getStatus(),
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
