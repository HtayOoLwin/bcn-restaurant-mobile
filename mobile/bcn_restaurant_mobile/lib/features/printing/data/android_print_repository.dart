import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/cashier_bill_print_result.dart';

/// Queues Sales Invoice HTML on Frappe for the Android Printer Worker.
/// The cashier app never connects directly to a Windows printer.
abstract interface class AndroidPrintGateway {
  Future<CashierBillPrintResult> requestCashierBill({
    required String salesOrder,
    required String requestId,
  });
}

class AndroidPrintRepository implements AndroidPrintGateway {
  const AndroidPrintRepository(this._apiClient);

  static const _requestCashierBillMethod = 'bcn_cashier_print_bill';
  final ApiClient _apiClient;

  @override
  Future<CashierBillPrintResult> requestCashierBill({
    required String salesOrder,
    required String requestId,
  }) async {
    final order = salesOrder.trim();
    final id = requestId.trim();
    if (order.isEmpty) {
      throw const FormatException('Sales Order is required for cashier print.');
    }
    if (id.isEmpty) {
      throw const FormatException('Print request ID is required.');
    }
    if (kDebugMode) {
      debugPrint('CASHIER_PRINT request sales_order=$order request_id=$id');
    }
    final data = await _apiClient.postMethod(
      _requestCashierBillMethod,
      data: {'sales_order': order, 'request_id': id},
    );
    if (data is! Map) {
      throw const FormatException('Print API returned an invalid response.');
    }
    final response = Map<String, dynamic>.from(data);
    if (kDebugMode) {
      debugPrint('CASHIER_PRINT response success=${response['success']} '
          'duplicate=${response['duplicate']} job=${response['print_job']} '
          'status=${response['status']} step=${response['step']} '
          'error=${response['error']}');
    }
    return CashierBillPrintResult.fromJson(response);
  }
}

final androidPrintRepositoryProvider = Provider<AndroidPrintGateway>(
  (ref) => AndroidPrintRepository(ref.watch(apiClientProvider)),
);
