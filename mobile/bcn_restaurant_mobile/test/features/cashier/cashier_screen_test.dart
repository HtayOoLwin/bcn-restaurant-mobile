import 'package:bcn_restaurant_mobile/core/network/api_client.dart';
import 'package:bcn_restaurant_mobile/core/storage/session_storage.dart';
import 'package:bcn_restaurant_mobile/features/auth/presentation/auth_controller.dart';
import 'package:bcn_restaurant_mobile/features/cashier/presentation/cashier_screen.dart';
import 'package:bcn_restaurant_mobile/features/printing/data/windows_print_repository.dart';
import 'package:bcn_restaurant_mobile/features/printing/domain/cashier_bill_print_result.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CashierScreen request-safe draft Sales Order flow', () {
    testWidgets('Open bill shows Print Bill and Payment', (tester) async {
      final api = _FakeApiClient(
        billingResponse: _billingResponse(restaurantStatus: 'Open'),
      );
      final printer = _FakePrintGateway();

      await _pumpCashier(
        tester,
        api: api,
        printer: printer,
        requestIds: ['REQ-A'],
      );

      expect(find.text('Print Bill'), findsOneWidget);
      expect(find.text('Payment'), findsOneWidget);
    });

    testWidgets('Billing failed bill shows Reprint, status, and Payment', (
      tester,
    ) async {
      final api = _FakeApiClient(
        billingResponse: _billingResponse(
          restaurantStatus: 'Billing',
          lastPrintStatus: 'Failed',
          lastPrintJob: 'PRINT-JOB-X',
        ),
      );
      final printer = _FakePrintGateway();

      await _pumpCashier(
        tester,
        api: api,
        printer: printer,
        requestIds: ['REQ-A'],
      );

      expect(find.text('Reprint Bill'), findsOneWidget);
      expect(find.text('Last Print: Failed'), findsOneWidget);
      expect(find.text('Payment'), findsOneWidget);
    });

    testWidgets('Failed print state never auto-reprints', (tester) async {
      final api = _FakeApiClient(
        billingResponse: _billingResponse(
          restaurantStatus: 'Billing',
          lastPrintStatus: 'Failed',
          lastPrintJob: 'PRINT-JOB-X',
        ),
      );
      final printer = _FakePrintGateway();

      await _pumpCashier(
        tester,
        api: api,
        printer: printer,
        requestIds: ['REQ-A'],
      );

      expect(printer.calls, isEmpty);
    });

    testWidgets(
      'transport retry reuses request id and later intentional reprint gets a new id',
      (tester) async {
        final api = _FakeApiClient(
          billingResponse: _billingResponse(
            restaurantStatus: 'Billing',
            lastPrintStatus: 'Failed',
            lastPrintJob: 'PRINT-JOB-X',
          ),
        );
        final printer = _FakePrintGateway(failuresRemaining: 1);

        await _pumpCashier(
          tester,
          api: api,
          printer: printer,
          requestIds: ['REQ-A', 'REQ-B'],
        );

        await tester.tap(find.text('Reprint Bill'));
        await tester.pumpAndSettle();
        expect(printer.calls, hasLength(1));
        expect(printer.calls[0].requestId, 'REQ-A');

        await tester.tap(find.text('Reprint Bill'));
        await tester.pumpAndSettle();
        expect(printer.calls, hasLength(2));
        expect(printer.calls[1].requestId, 'REQ-A');

        await tester.tap(find.text('Reprint Bill'));
        await tester.pumpAndSettle();
        expect(printer.calls, hasLength(3));
        expect(printer.calls[2].requestId, 'REQ-B');
      },
    );

    testWidgets('payment success offers manual finalized Sales Order reprint', (
      tester,
    ) async {
      final api = _FakeApiClient(
        billingResponse: _billingResponse(restaurantStatus: 'Open'),
        paymentResponse: const {
          'sales_order': 'SAL-ORD-2026-00005',
          'sales_invoice': 'ACC-SINV-2026-00001',
          'payment_entries': ['ACC-PAY-2026-00001'],
          'change_amount': 0,
          'duplicate': false,
        },
        removeBillAfterPayment: true,
      );
      final printer = _FakePrintGateway();

      await _pumpCashier(
        tester,
        api: api,
        printer: printer,
        requestIds: ['REQ-POST-PAY'],
      );

      await tester.tap(find.text('Payment'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm Payment'), findsOneWidget);

      await tester.tap(find.text('Confirm Payment'));
      await tester.pumpAndSettle();

      expect(api.paymentSalesOrders, ['SAL-ORD-2026-00005']);
      expect(find.text('Reprint Bill'), findsOneWidget);

      await tester.tap(find.text('Reprint Bill'));
      await tester.pumpAndSettle();

      expect(printer.calls, hasLength(1));
      expect(printer.calls.single.salesOrder, 'SAL-ORD-2026-00005');
      expect(printer.calls.single.requestId, 'REQ-POST-PAY');
    });
  });
}

Future<void> _pumpCashier(
  WidgetTester tester, {
  required _FakeApiClient api,
  required _FakePrintGateway printer,
  required List<String> requestIds,
}) async {
  var requestIndex = 0;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        windowsPrintRepositoryProvider.overrideWithValue(printer),
        cashierPrintRequestIdFactoryProvider.overrideWithValue(
          () => requestIds[requestIndex++],
        ),
      ],
      child: const MaterialApp(home: CashierScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

Map<String, dynamic> _billingResponse({
  required String restaurantStatus,
  String? lastPrintStatus,
  String? lastPrintJob,
}) {
  return {
    'bills': [
      {
        'sales_order': 'SAL-ORD-2026-00005',
        'customer': 'Table 01',
        'customer_name': 'Table 01',
        'creation': '2026-09-07 09:00:00',
        'net_total': 10000,
        'total_taxes_and_charges': 500,
        'grand_total': 10500,
        'currency': 'MMK',
        'restaurant_status': restaurantStatus,
        'last_print_status': lastPrintStatus,
        'last_print_job': lastPrintJob,
        'items': [],
        'taxes': [],
      },
    ],
    'modes': [
      {'name': 'Cash', 'default': true},
    ],
  };
}

class _FakePrintGateway implements WindowsPrintGateway {
  _FakePrintGateway({this.failuresRemaining = 0});

  int failuresRemaining;
  final List<({String salesOrder, String requestId})> calls = [];

  @override
  Future<CashierBillPrintResult> requestCashierBill({
    required String salesOrder,
    required String requestId,
  }) async {
    calls.add((salesOrder: salesOrder, requestId: requestId));
    if (failuresRemaining > 0) {
      failuresRemaining -= 1;
      throw Exception('transport unavailable');
    }
    return CashierBillPrintResult(
      salesOrder: salesOrder,
      requestId: requestId,
      printJob: 'PRINT-${calls.length}',
      status: 'Pending',
      isReprint: calls.length > 1,
      duplicate: false,
    );
  }
}

class _FakeApiClient extends ApiClient {
  _FakeApiClient({
    required this.billingResponse,
    this.paymentResponse = const {
      'sales_order': 'SAL-ORD-2026-00005',
      'sales_invoice': 'ACC-SINV-2026-00001',
      'payment_entries': ['ACC-PAY-2026-00001'],
      'change_amount': 0,
      'duplicate': false,
    },
    this.removeBillAfterPayment = false,
  }) : super(sessionStorage: _MemorySessionStorage());

  Map<String, dynamic> billingResponse;
  final Map<String, dynamic> paymentResponse;
  final bool removeBillAfterPayment;
  final List<String> paymentSalesOrders = [];

  @override
  Future<bool> hasSession() async => false;

  @override
  Future<dynamic> getMethod(
    String method, {
    Map<String, dynamic>? queryParameters,
  }) async {
    if (method == 'bcn_cashier_billing') {
      return billingResponse;
    }
    if (method == 'bcn_mobile_tables') {
      return {
        'service_type': queryParameters?['service_type'] ?? 'dine_in',
        'customer_group': '',
        'tables': const [],
      };
    }
    throw StateError('Unexpected GET method: $method');
  }

  @override
  Future<dynamic> postMethod(
    String method, {
    Map<String, dynamic>? data,
  }) async {
    if (method != 'bcn_cashier_billing') {
      throw StateError('Unexpected POST method: $method');
    }
    paymentSalesOrders.add(data?['sales_order']?.toString() ?? '');
    if (removeBillAfterPayment) {
      billingResponse = {
        'bills': const [],
        'modes': billingResponse['modes'] ?? const [],
      };
    }
    return paymentResponse;
  }
}

class _MemorySessionStorage extends SessionStorage {
  @override
  Future<String?> readSid() async => null;

  @override
  Future<void> writeSid(String sid) async {}

  @override
  Future<void> clearSid() async {}
}
