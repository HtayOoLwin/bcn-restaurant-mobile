import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/windows_print_status.dart';

abstract interface class WindowsPrintGateway {
  Future<PrintRequestResult> requestCashierBill(String invoiceName);

  Future<WindowsPrintStatus> getStatus();

  Future<void> retryJob(String jobId);
}

class WindowsPrintRepository implements WindowsPrintGateway {
  const WindowsPrintRepository(this._apiClient);

  static const _requestCashierBillMethod =
      'bcn_restaurant.api.printing.request_cashier_bill';
  static const _getStatusMethod =
      'bcn_restaurant.api.printing.get_print_status';
  static const _retryJobMethod = 'bcn_restaurant.api.printing.retry_print_job';

  final ApiClient _apiClient;

  @override
  Future<PrintRequestResult> requestCashierBill(String invoiceName) async {
    final data = await _apiClient.postMethod(
      _requestCashierBillMethod,
      data: {'invoice_name': invoiceName},
    );
    return PrintRequestResult.fromJson(_responseMap(data));
  }

  @override
  Future<WindowsPrintStatus> getStatus() async {
    final data = await _apiClient.getMethod(_getStatusMethod);
    return WindowsPrintStatus.fromJson(_responseMap(data));
  }

  @override
  Future<void> retryJob(String jobId) async {
    final data = await _apiClient.postMethod(
      _retryJobMethod,
      data: {'job_id': jobId},
    );
    final response = _responseMap(data);
    PrintJobStatusValue.parse(response['status']);
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
