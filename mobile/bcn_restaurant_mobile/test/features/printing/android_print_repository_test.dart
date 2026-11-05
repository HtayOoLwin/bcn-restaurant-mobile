import 'package:bcn_restaurant_mobile/core/network/api_client.dart';
import 'package:bcn_restaurant_mobile/core/storage/session_storage.dart';
import 'package:bcn_restaurant_mobile/features/printing/data/android_print_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android print gateway sends cashier Sales Order and request ID', () async {
    final api = _FakeApiClient({
      'success': true,
      'sales_order': 'SAL-ORD-2026-00216',
      'request_id': 'REQ-ANDROID-1',
      'print_job': 'PRINT-JOB-1',
      'status': 'Pending',
      'duplicate': false,
    });

    final result = await AndroidPrintRepository(api).requestCashierBill(
      salesOrder: ' SAL-ORD-2026-00216 ',
      requestId: ' REQ-ANDROID-1 ',
    );

    expect(api.method, 'bcn_cashier_print_bill');
    expect(api.payload, {
      'sales_order': 'SAL-ORD-2026-00216',
      'request_id': 'REQ-ANDROID-1',
      'print_source': 'cashier',
    });
    expect(result.printJob, 'PRINT-JOB-1');
    expect(result.status, 'Pending');
  });

  test('Daily Sales reprint sends daily_report source', () async {
    final api = _FakeApiClient({
      'success': true,
      'sales_order': 'SAL-ORD-2026-00216',
      'request_id': 'REQ-DAILY-1',
      'print_job': 'PRINT-JOB-2',
      'status': 'Pending',
      'duplicate': false,
    });
    final result = await AndroidPrintRepository(api).requestCashierBill(
      salesOrder: 'SAL-ORD-2026-00216',
      requestId: 'REQ-DAILY-1',
      printSource: 'daily_report',
    );
    expect(api.payload?['print_source'], 'daily_report');
    expect(result.printJob, 'PRINT-JOB-2');
  });

  test('HTTP 200 with success false exposes Frappe step and error', () async {
    final api = _FakeApiClient({
      'success': false,
      'step': 'SAVE BCN PRINT JOB',
      'error': 'Permission denied',
      'print_job': '',
    });

    expect(
      () => AndroidPrintRepository(api).requestCashierBill(
        salesOrder: 'SAL-ORD-2026-00216',
        requestId: 'REQ-ANDROID-2',
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('SAVE BCN PRINT JOB: Permission denied'),
        ),
      ),
    );
  });
}

class _FakeApiClient extends ApiClient {
  _FakeApiClient(this.response)
      : super(
          sessionStorage: SessionStorage(storage: const FlutterSecureStorage()),
          dio: Dio(),
        );

  final Map<String, dynamic> response;
  String? method;
  Map<String, dynamic>? payload;

  @override
  Future<dynamic> postMethod(String method, {Map<String, dynamic>? data}) async {
    this.method = method;
    payload = data;
    return response;
  }
}
