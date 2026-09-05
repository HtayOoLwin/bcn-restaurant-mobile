import 'dart:async';

import 'package:bcn_restaurant_mobile/core/network/api_exception.dart';
import 'package:bcn_restaurant_mobile/features/auth/domain/auth_state.dart';
import 'package:bcn_restaurant_mobile/features/auth/presentation/auth_controller.dart';
import 'package:bcn_restaurant_mobile/features/cashier/domain/cashier_models.dart';
import 'package:bcn_restaurant_mobile/features/cashier/presentation/cashier_screen.dart';
import 'package:bcn_restaurant_mobile/features/printing/data/windows_print_repository.dart';
import 'package:bcn_restaurant_mobile/features/printing/domain/windows_print_status.dart';
import 'package:bcn_restaurant_mobile/features/printing/presentation/printer_settings_screen.dart';
import 'package:bcn_restaurant_mobile/features/settings/presentation/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('settings links to the Windows print service', (tester) async {
    var printerOpened = false;
    var loggedOut = false;

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsView(
          fullName: 'Cashier User',
          user: 'cashier@example.com',
          serverUrl: 'https://restaurant.example.com',
          appVersion: 'v1.2.3 (45)',
          onPrinterSetup: () => printerOpened = true,
          onLogout: () => loggedOut = true,
        ),
      ),
    );

    expect(find.text('Windows Print Service'), findsOneWidget);
    expect(find.text('Server-managed printer jobs and status'), findsOneWidget);

    await tester.tap(find.text('Windows Print Service'));
    expect(printerOpened, isTrue);

    await tester.ensureVisible(find.text('Log Out'));
    await tester.tap(find.text('Log Out'));
    expect(loggedOut, isTrue);
  });

  testWidgets(
    'cashier sends one request while pending and reports job acceptance',
    (tester) async {
      final request = Completer<PrintRequestResult>();
      final repository = _FakeWindowsPrintGateway(request: request.future);

      await tester.pumpWidget(_cashierHarness(repository));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Print Bill'));
      await tester.tap(find.text('Print Bill'));
      await tester.pump();

      expect(repository.requestedInvoices, ['SINV-0001']);
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Sending…'),
      );
      expect(button.onPressed, isNull);

      request.complete(_pendingResult());
      await tester.pumpAndSettle();

      expect(find.text('Print job sent'), findsOneWidget);
      expect(find.text('Bill printed.'), findsNothing);
    },
  );

  testWidgets('cashier keeps an API error visible', (tester) async {
    final repository = _FakeWindowsPrintGateway(
      requestError: const ApiException('No cashier printer configured.'),
    );

    await tester.pumpWidget(_cashierHarness(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Print Bill'));
    await tester.pumpAndSettle();

    expect(find.text('No cashier printer configured.'), findsOneWidget);
  });

  testWidgets('cashier completion after disposal does not touch dead state', (
    tester,
  ) async {
    final request = Completer<PrintRequestResult>();
    final repository = _FakeWindowsPrintGateway(request: request.future);

    await tester.pumpWidget(_cashierHarness(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Print Bill'));
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));

    request.complete(_pendingResult());
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('shows Windows status and refreshes after test print and retry', (
    tester,
  ) async {
    final repository = _FakeWindowsPrintGateway(
      request: Future.value(_pendingResult()),
      status: const WindowsPrintStatus(
        online: true,
        lastSeen: '2026-09-05 10:11:12',
        pending: 2,
        failed: 3,
      ),
    );

    await tester.pumpWidget(
      _printerHarness(repository, invoice: _invoice(), canRetryPrintJobs: true),
    );
    await tester.pumpAndSettle();

    expect(find.text('Windows Print Service'), findsOneWidget);
    expect(find.text('Online'), findsOneWidget);
    expect(find.text('Last seen: 2026-09-05 10:11:12'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Bluetooth'), findsNothing);
    expect(find.text('Choose Bluetooth Printer'), findsNothing);
    expect(find.text('Test Cashier Print'), findsOneWidget);
    expect(find.text('Retry Failed Jobs'), findsOneWidget);

    await tester.tap(find.text('Test Cashier Print'));
    await tester.pumpAndSettle();
    expect(repository.requestedInvoices, ['SINV-0001']);
    expect(find.text('Print job sent'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('failed-print-job-id')),
      '10ba038e-48da-487b-96e8-8d3b99b6d18a',
    );
    await tester.tap(find.text('Retry Failed Jobs'));
    await tester.pumpAndSettle();

    expect(repository.retriedJobIds, ['10ba038e-48da-487b-96e8-8d3b99b6d18a']);
    expect(repository.statusRequests, greaterThanOrEqualTo(3));
  });

  testWidgets('hides retry without authorization', (tester) async {
    final repository = _FakeWindowsPrintGateway(
      status: const WindowsPrintStatus(
        online: false,
        lastSeen: null,
        pending: 0,
        failed: 2,
      ),
    );

    await tester.pumpWidget(
      _printerHarness(repository, canRetryPrintJobs: false),
    );
    await tester.pumpAndSettle();

    expect(find.text('Offline'), findsOneWidget);
    expect(find.text('Retry Failed Jobs'), findsNothing);
    expect(find.byKey(const Key('failed-print-job-id')), findsNothing);
  });

  testWidgets(
    'hides test print for missing, draft, or invalid invoice context',
    (tester) async {
      final repository = _FakeWindowsPrintGateway();

      await tester.pumpWidget(_printerHarness(repository));
      await tester.pumpAndSettle();
      expect(find.text('Test Cashier Print'), findsNothing);

      await tester.pumpWidget(
        _printerHarness(repository, invoice: _invoice(docstatus: 0)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Test Cashier Print'), findsNothing);

      await tester.pumpWidget(
        _printerHarness(repository, invoice: _invoice(name: '', docstatus: 1)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Test Cashier Print'), findsNothing);
    },
  );

  testWidgets('retry prevents duplicate taps and reports API errors', (
    tester,
  ) async {
    final retry = Completer<void>();
    final repository = _FakeWindowsPrintGateway(
      retry: retry.future,
      status: const WindowsPrintStatus(
        online: true,
        lastSeen: null,
        pending: 0,
        failed: 1,
      ),
    );

    await tester.pumpWidget(
      _printerHarness(repository, canRetryPrintJobs: true),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('failed-print-job-id')),
      '10ba038e-48da-487b-96e8-8d3b99b6d18a',
    );
    await tester.tap(find.text('Retry Failed Jobs'));
    await tester.tap(find.text('Retry Failed Jobs'));
    await tester.pump();

    expect(repository.retriedJobIds, hasLength(1));

    retry.completeError(const ApiException('Retry is not allowed.'));
    await tester.pumpAndSettle();

    expect(find.text('Retry is not allowed.'), findsOneWidget);
    expect(repository.statusRequests, greaterThanOrEqualTo(2));
  });
}

Widget _cashierHarness(WindowsPrintGateway repository) {
  return ProviderScope(
    overrides: [
      authControllerProvider.overrideWith(_TestAuthController.new),
      windowsPrintRepositoryProvider.overrideWithValue(repository),
      cashierBillingProvider.overrideWith((ref) async => _billing()),
    ],
    child: const MaterialApp(home: CashierScreen()),
  );
}

Widget _printerHarness(
  WindowsPrintGateway repository, {
  CashierInvoice? invoice,
  bool canRetryPrintJobs = false,
}) {
  return ProviderScope(
    overrides: [windowsPrintRepositoryProvider.overrideWithValue(repository)],
    child: MaterialApp(
      home: PrinterSettingsScreen(
        invoice: invoice,
        canRetryPrintJobs: canRetryPrintJobs,
      ),
    ),
  );
}

PrintRequestResult _pendingResult() => PrintRequestResult.fromJson({
  'job_id': '10ba038e-48da-487b-96e8-8d3b99b6d18a',
  'status': 'Pending',
  'is_reprint': false,
});

CashierBillingResponse _billing() => CashierBillingResponse(
  invoices: [_invoice()],
  modes: const [],
  printerSettings: const CashierPrinterSettings(
    printerIp: '',
    printerPort: 9100,
    paperWidth: '80mm',
  ),
);

CashierInvoice _invoice({String name = 'SINV-0001', int docstatus = 1}) {
  return CashierInvoice.fromJson({
    'name': name,
    'customer': 'Table 1',
    'customer_name': 'Table 1',
    'creation': '2026-09-05 10:00:00',
    'net_total': 1000,
    'total_taxes_and_charges': 0,
    'grand_total': 1000,
    'outstanding_amount': 1000,
    'currency': 'MMK',
    'docstatus': docstatus,
    'payment_status': 'Unpaid',
    'sales_orders': ['SO-0001'],
    'items': const [],
    'taxes': const [],
    'bill_printed': false,
    'bill_printed_total': 0,
  });
}

class _FakeWindowsPrintGateway implements WindowsPrintGateway {
  _FakeWindowsPrintGateway({
    Future<PrintRequestResult>? request,
    this.requestError,
    Future<void>? retry,
    this.status = const WindowsPrintStatus(
      online: true,
      lastSeen: null,
      pending: 0,
      failed: 0,
    ),
  }) : _request = request ?? Future.value(_pendingResult()),
       _retry = retry ?? Future<void>.value();

  final Future<PrintRequestResult> _request;
  final Object? requestError;
  final Future<void> _retry;
  final WindowsPrintStatus status;
  final List<String> requestedInvoices = [];
  final List<String> retriedJobIds = [];
  int statusRequests = 0;

  @override
  Future<PrintRequestResult> requestCashierBill(String invoiceName) {
    requestedInvoices.add(invoiceName);
    final error = requestError;
    if (error != null) return Future.error(error);
    return _request;
  }

  @override
  Future<WindowsPrintStatus> getStatus() async {
    statusRequests += 1;
    return status;
  }

  @override
  Future<void> retryJob(String jobId) {
    retriedJobIds.add(jobId);
    return _retry;
  }
}

class _TestAuthController extends AuthController {
  @override
  Future<AuthState> build() async => const AuthState.unauthenticated();
}
