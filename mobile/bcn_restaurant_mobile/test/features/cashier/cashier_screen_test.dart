import 'package:bcn_restaurant_mobile/core/network/api_client.dart';
import 'package:bcn_restaurant_mobile/core/storage/session_storage.dart';
import 'package:bcn_restaurant_mobile/features/auth/presentation/auth_controller.dart';
import 'package:bcn_restaurant_mobile/features/cashier/presentation/cashier_screen.dart';
import 'package:bcn_restaurant_mobile/features/printing/data/android_print_repository.dart';
import 'package:bcn_restaurant_mobile/features/printing/domain/cashier_bill_print_result.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _billingCardColor = Color(0xFFE9F8EF);
const _openCardColor = Colors.white;
const _reprintBlue = Color(0xFF0D47A1);
const _paymentGreen = Color(0xFF0B6B3A);
const _disabledBackground = Color(0xFFE2E8F0);
const _disabledForeground = Color(0xFF94A3B8);

void main() {
  group('CashierScreen payment and Android receipt printing', () {
    testWidgets('Billing order shows Pay and Credit before and after expansion',
        (tester) async {
      final api = _FakeApiClient(
        billingResponse: _billingResponse(restaurantStatus: 'Billing'),
      );
      final printer = _FakePrintGateway();
      await _pumpCashier(tester,
          api: api, printer: printer, requestIds: ['REQ-A']);

      expect(find.text('Table 01'), findsOneWidget);
      expect(find.text('SAL-ORD-2026-00005'), findsOneWidget);
      expect(find.byIcon(Icons.expand_more), findsOneWidget);
      expect(find.text('Grand Total'), findsNothing);
      expect(find.text('Pay'), findsOneWidget);
      expect(find.text('Credit'), findsOneWidget);
      expect(find.text('Reprint Bill'), findsNothing);

      await _expandBill(tester);
      expect(find.byIcon(Icons.expand_less), findsOneWidget);
      expect(find.text('Grand Total'), findsOneWidget);
      expect(find.text('Pay'), findsOneWidget);
      expect(find.text('Credit'), findsOneWidget);
    });

    testWidgets('Billing order uses green card and active Pay and Credit',
        (tester) async {
      final api = _FakeApiClient(
        billingResponse: _billingResponse(
          restaurantStatus: 'Billing',
          lastPrintStatus: 'Printed',
          lastPrintJob: 'PRINT-JOB-X',
        ),
      );
      await _pumpCashier(tester,
          api: api, printer: _FakePrintGateway(), requestIds: ['REQ-A']);
      final card = tester.widget<Card>(
        find.ancestor(
            of: find.text('Table 01'), matching: find.byType(Card)).first,
      );
      expect(card.color, _billingCardColor);
      final pay = _filledButton(tester, 'Pay');
      final credit = _filledButton(tester, 'Credit');
      expect(pay.onPressed, isNotNull);
      expect(credit.onPressed, isNotNull);
      expect(pay.style?.backgroundColor?.resolve({}), _paymentGreen);
      expect(credit.style?.backgroundColor?.resolve({}),
          const Color(0xFFC62828));
    });

    testWidgets('Open order permits checkout with Pay and Credit',
        (tester) async {
      final api = _FakeApiClient(
        billingResponse: _billingResponse(restaurantStatus: 'Open'),
      );
      await _pumpCashier(tester,
          api: api, printer: _FakePrintGateway(), requestIds: ['REQ-A']);
      final card = tester.widget<Card>(
        find.ancestor(
            of: find.text('Table 01'), matching: find.byType(Card)).first,
      );
      expect(card.color, _billingCardColor);
      expect(_filledButton(tester, 'Pay').onPressed, isNotNull);
      expect(_filledButton(tester, 'Credit').onPressed, isNotNull);
      await _expandBill(tester);
      expect(_filledButton(tester, 'Pay').onPressed, isNotNull);
      expect(_filledButton(tester, 'Credit').onPressed, isNotNull);
    });

    testWidgets('Failed prior print does not auto-queue another receipt',
        (tester) async {
      final api = _FakeApiClient(
        billingResponse: _billingResponse(
          restaurantStatus: 'Billing',
          lastPrintStatus: 'Failed',
          lastPrintJob: 'PRINT-JOB-X',
        ),
      );
      final printer = _FakePrintGateway();
      await _pumpCashier(tester,
          api: api, printer: printer, requestIds: ['REQ-A']);
      await _expandBill(tester);
      expect(find.text('Pay'), findsOneWidget);
      expect(find.text('Credit'), findsOneWidget);
      expect(printer.calls, isEmpty);
    });

    testWidgets('Transport retry reuses request id without repeating payment',
        (tester) async {
      final api = _FakeApiClient(
        billingResponse: _billingResponse(restaurantStatus: 'Billing'),
        removeBillAfterPayment: true,
      );
      final printer = _FakePrintGateway(failuresRemaining: 1);
      await _pumpCashier(tester,
          api: api, printer: printer, requestIds: ['REQ-A', 'REQ-B']);

      await _completePaymentAndChoosePrint(tester);
      expect(printer.calls, hasLength(1));
      expect(printer.calls[0].requestId, 'REQ-A');
      expect(find.text('Cashier print failed'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Retry Print'));
      await tester.pumpAndSettle();
      expect(printer.calls, hasLength(2));
      expect(printer.calls[1].requestId, 'REQ-A');
      expect(api.paymentActions, ['Pay', 'ConfirmPayment']);
    });

    testWidgets('Successful payment prints even after bill leaves active list',
        (tester) async {
      final api = _FakeApiClient(
        billingResponse: _billingResponse(
          restaurantStatus: 'Billing',
          lastPrintStatus: 'Printed',
          lastPrintJob: 'PRINT-JOB-X',
        ),
        removeBillAfterPayment: true,
      );
      final printer = _FakePrintGateway();
      await _pumpCashier(tester,
          api: api, printer: printer, requestIds: ['REQ-POST-PAY']);

      await _completePaymentAndChoosePrint(tester);
      await tester.pumpAndSettle();
      expect(api.paymentSalesOrders, [
        'SAL-ORD-2026-00005',
        'SAL-ORD-2026-00005',
      ]);
      expect(api.paymentActions, ['Pay', 'ConfirmPayment']);
      expect(printer.calls, hasLength(1));
      expect(printer.calls.single.salesOrder, 'SAL-ORD-2026-00005');
      expect(printer.calls.single.requestId, 'REQ-POST-PAY');
    });
  });
}

Future<void> _completePaymentAndChoosePrint(WidgetTester tester) async {
  await tester.tap(find.text('Pay'));
  await tester.pumpAndSettle();
  expect(find.text('Confirm Payment'), findsOneWidget);
  await tester.tap(find.text('Confirm Payment'));
  await tester.pumpAndSettle();
  expect(find.text('Yes, Print'), findsOneWidget);
  await tester.tap(find.text('Yes, Print'));
  await tester.pumpAndSettle();
}

FilledButton _filledButton(WidgetTester tester, String label) {
  return tester.widget<FilledButton>(
    find.widgetWithText(FilledButton, label),
  );
}

Future<void> _expandBill(WidgetTester tester) async {
  await tester.tap(find.text('Table 01'));
  await tester.pumpAndSettle();
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
        androidPrintRepositoryProvider.overrideWithValue(printer),
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

class _FakePrintGateway implements AndroidPrintGateway {
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
  final List<String> paymentActions = [];

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
    final action = data?['action']?.toString() ?? '';
    paymentSalesOrders.add(data?['sales_order']?.toString() ?? '');
    paymentActions.add(action);
    if (action == 'Pay') {
      return {
        'sales_order': data?['sales_order'],
        'sales_invoice': 'ACC-SINV-2026-00001',
        'restaurant_status': 'Payment Pending',
        'duplicate': false,
      };
    }
    if (action != 'ConfirmPayment') {
      throw StateError('Unexpected cashier action: $action');
    }
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
