import 'package:bcn_restaurant_mobile/core/network/api_client.dart';
import 'package:bcn_restaurant_mobile/core/storage/session_storage.dart';
import 'package:bcn_restaurant_mobile/features/printing/data/windows_print_repository.dart';
import 'package:bcn_restaurant_mobile/features/printing/domain/windows_print_status.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WindowsPrintRepository', () {
    test('requests a cashier bill through the exact POST contract', () async {
      final api = _RecordingApiClient(
        postResponse: {
          'job_id': '10ba038e-48da-487b-96e8-8d3b99b6d18a',
          'status': 'Pending',
          'is_reprint': false,
        },
      );

      final result = await WindowsPrintRepository(
        api,
      ).requestCashierBill('SINV-0001');

      expect(api.postCalls, hasLength(1));
      expect(
        api.postCalls.single.method,
        'bcn_restaurant.api.printing.request_cashier_bill',
      );
      expect(api.postCalls.single.data, {'invoice_name': 'SINV-0001'});
      expect(result.jobId, '10ba038e-48da-487b-96e8-8d3b99b6d18a');
      expect(result.status.state, PrintJobState.pending);
      expect(result.status.rawValue, 'Pending');
      expect(result.isReprint, isFalse);
    });

    test('gets Windows status through the exact GET contract', () async {
      final api = _RecordingApiClient(
        getResponse: {
          'online': true,
          'last_seen': '2026-09-05 10:11:12',
          'pending': 2,
          'failed': 3,
        },
      );

      final status = await WindowsPrintRepository(api).getStatus();

      expect(api.getCalls, hasLength(1));
      expect(
        api.getCalls.single.method,
        'bcn_restaurant.api.printing.get_print_status',
      );
      expect(api.getCalls.single.queryParameters, isNull);
      expect(status.online, isTrue);
      expect(status.lastSeen, '2026-09-05 10:11:12');
      expect(status.pending, 2);
      expect(status.failed, 3);
    });

    test('retries one job through the exact POST contract', () async {
      final api = _RecordingApiClient(postResponse: {'status': 'Pending'});

      await WindowsPrintRepository(
        api,
      ).retryJob('10ba038e-48da-487b-96e8-8d3b99b6d18a');

      expect(api.postCalls, hasLength(1));
      expect(
        api.postCalls.single.method,
        'bcn_restaurant.api.printing.retry_print_job',
      );
      expect(api.postCalls.single.data, {
        'job_id': '10ba038e-48da-487b-96e8-8d3b99b6d18a',
      });
    });

    test('preserves an unknown server job status safely', () {
      final result = PrintRequestResult.fromJson({
        'job_id': '10ba038e-48da-487b-96e8-8d3b99b6d18a',
        'status': 'QueuedByVendor',
        'is_reprint': 1,
      });

      expect(result.status.state, PrintJobState.unknown);
      expect(result.status.rawValue, 'QueuedByVendor');
      expect(result.isReprint, isTrue);
    });

    test('rejects a malformed response envelope', () async {
      final api = _RecordingApiClient(postResponse: {'status': 'Pending'});

      expect(
        () => WindowsPrintRepository(api).requestCashierBill('SINV-0001'),
        throwsFormatException,
      );
    });

    test(
      'consumes the ApiClient Frappe message envelope exactly once',
      () async {
        final requests = <RequestOptions>[];
        final dio = Dio(BaseOptions(baseUrl: 'https://restaurant.example.com'));
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
                      'job_id': '858f9d28-9799-49d7-8a03-7ed83bd37a5b',
                      'status': 'Pending',
                      'is_reprint': false,
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

        final result = await WindowsPrintRepository(
          client,
        ).requestCashierBill('SINV-0002');

        expect(result.jobId, '858f9d28-9799-49d7-8a03-7ed83bd37a5b');
        expect(result.status.state, PrintJobState.pending);
        expect(requests, hasLength(1));
        expect(
          requests.single.path,
          '/api/method/bcn_restaurant.api.printing.request_cashier_bill',
        );
        expect(requests.single.method, 'POST');
        expect(requests.single.data, {'invoice_name': 'SINV-0002'});
      },
    );
  });
}

class _MemorySessionStorage extends SessionStorage {
  _MemorySessionStorage() : super(storage: const FlutterSecureStorage());

  @override
  Future<String?> readSid() async => 'test-session';
}

class _RecordingApiClient extends ApiClient {
  _RecordingApiClient({this.getResponse, this.postResponse})
    : super(
        sessionStorage: SessionStorage(storage: const FlutterSecureStorage()),
        dio: Dio(),
      );

  final dynamic getResponse;
  final dynamic postResponse;
  final List<({String method, Map<String, dynamic>? queryParameters})>
  getCalls = [];
  final List<({String method, Map<String, dynamic>? data})> postCalls = [];

  @override
  Future<dynamic> getMethod(
    String method, {
    Map<String, dynamic>? queryParameters,
  }) async {
    getCalls.add((method: method, queryParameters: queryParameters));
    return getResponse;
  }

  @override
  Future<dynamic> postMethod(
    String method, {
    Map<String, dynamic>? data,
  }) async {
    postCalls.add((method: method, data: data));
    return postResponse;
  }
}
