import 'package:bcn_restaurant_mobile/core/network/api_client.dart';
import 'package:bcn_restaurant_mobile/core/storage/session_storage.dart';
import 'package:bcn_restaurant_mobile/features/printing/data/windows_print_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WindowsPrintRepository', () {
    test('queues cashier bill with request id through OurCity alias', () async {
      final api = _RecordingApiClient(
        postResponse: {
          'sales_order': 'SAL-ORD-2026-00005',
          'request_id': 'REQ-A',
          'print_job': 'PRINT-JOB-X',
          'status': 'Pending',
          'is_reprint': false,
          'duplicate': false,
        },
      );

      final result = await WindowsPrintRepository(api).requestCashierBill(
        salesOrder: 'SAL-ORD-2026-00005',
        requestId: 'REQ-A',
      );

      expect(api.postCalls, hasLength(1));
      expect(api.postCalls.single.method, 'bcn_cashier_print_bill');
      expect(api.postCalls.single.data, {
        'sales_order': 'SAL-ORD-2026-00005',
        'request_id': 'REQ-A',
      });
      expect(result.salesOrder, 'SAL-ORD-2026-00005');
      expect(result.requestId, 'REQ-A');
      expect(result.printJob, 'PRINT-JOB-X');
      expect(result.status, 'Pending');
      expect(result.isReprint, isFalse);
      expect(result.duplicate, isFalse);
    });

    test('reuses the caller supplied request id unchanged', () async {
      final api = _RecordingApiClient(
        postResponse: {
          'sales_order': 'SAL-ORD-2026-00005',
          'request_id': 'REQ-STABLE',
          'print_job': 'PRINT-JOB-X',
          'status': 'Pending',
          'is_reprint': false,
          'duplicate': true,
        },
      );
      final repository = WindowsPrintRepository(api);

      await repository.requestCashierBill(
        salesOrder: 'SAL-ORD-2026-00005',
        requestId: 'REQ-STABLE',
      );
      await repository.requestCashierBill(
        salesOrder: 'SAL-ORD-2026-00005',
        requestId: 'REQ-STABLE',
      );

      expect(api.postCalls, hasLength(2));
      expect(api.postCalls[0].data?['request_id'], 'REQ-STABLE');
      expect(api.postCalls[1].data?['request_id'], 'REQ-STABLE');
    });

    test('consumes the ApiClient Frappe message envelope exactly once', () async {
      final requests = <RequestOptions>[];
      final dio = Dio(BaseOptions(baseUrl: 'https://ourcity.s.frappe.cloud'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options);
            handler.resolve(
              Response<dynamic>(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'message': {
                    'sales_order': 'SAL-ORD-2026-00005',
                    'request_id': 'REQ-A',
                    'print_job': 'PRINT-JOB-X',
                    'status': 'Pending',
                    'is_reprint': false,
                    'duplicate': false,
                  },
                },
              ),
            );
          },
        ),
      );
      final client = ApiClient(
        sessionStorage: _MemorySessionStorage(),
        dio: dio,
      );

      final result = await WindowsPrintRepository(client).requestCashierBill(
        salesOrder: 'SAL-ORD-2026-00005',
        requestId: 'REQ-A',
      );

      expect(result.printJob, 'PRINT-JOB-X');
      expect(result.requestId, 'REQ-A');
      expect(requests, hasLength(1));
      expect(requests.single.path, '/api/method/bcn_cashier_print_bill');
      expect(requests.single.method, 'POST');
      expect(requests.single.data, {
        'sales_order': 'SAL-ORD-2026-00005',
        'request_id': 'REQ-A',
      });
    });
  });
}

class _MemorySessionStorage extends SessionStorage {
  _MemorySessionStorage() : super(storage: const FlutterSecureStorage());

  @override
  Future<String?> readSid() async => 'test-session';
}

class _RecordingApiClient extends ApiClient {
  _RecordingApiClient({this.postResponse})
    : super(
        sessionStorage: SessionStorage(storage: const FlutterSecureStorage()),
        dio: Dio(),
      );

  final dynamic postResponse;
  final List<({String method, Map<String, dynamic>? data})> postCalls = [];

  @override
  Future<dynamic> postMethod(
    String method, {
    Map<String, dynamic>? data,
  }) async {
    postCalls.add((method: method, data: data));
    return postResponse;
  }
}
