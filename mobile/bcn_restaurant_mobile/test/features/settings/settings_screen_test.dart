import 'dart:async';

import 'package:bcn_restaurant_mobile/core/network/api_exception.dart';
import 'package:bcn_restaurant_mobile/core/router/app_router.dart';
import 'package:bcn_restaurant_mobile/features/auth/domain/auth_state.dart';
import 'package:bcn_restaurant_mobile/features/auth/presentation/auth_controller.dart';
import 'package:bcn_restaurant_mobile/features/bootstrap/domain/bootstrap_model.dart';
import 'package:bcn_restaurant_mobile/features/cashier/domain/cashier_models.dart';
import 'package:bcn_restaurant_mobile/features/cashier/presentation/cashier_screen.dart';
import 'package:bcn_restaurant_mobile/features/printing/data/windows_print_repository.dart';
import 'package:bcn_restaurant_mobile/features/printing/domain/known_print_job_controller.dart';
import 'package:bcn_restaurant_mobile/features/printing/domain/windows_print_status.dart';
import 'package:bcn_restaurant_mobile/features/printing/presentation/printer_settings_screen.dart';
import 'package:bcn_restaurant_mobile/features/settings/presentation/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bootstrap print flags are parsed as strict server booleans', () {
    final allowed = BootstrapModel.fromJson({
      'permissions': {
        'manager': true,
        'can_view_print_status': true,
        'can_retry_print_jobs': true,
      },
    });
    final denied = BootstrapModel.fromJson({
      'permissions': {
        'can_view_print_status': 'true',
        'can_retry_print_jobs': 1,
      },
    });

    expect(allowed.permissions.manager, isTrue);
    expect(allowed.permissions.canViewPrintStatus, isTrue);
    expect(allowed.permissions.canRetryPrintJobs, isTrue);
    expect(denied.permissions.canViewPrintStatus, isFalse);
    expect(denied.permissions.canRetryPrintJobs, isFalse);
  });

  testWidgets('settings preserves printer navigation and logout actions', (
    tester,
  ) async {
    var printerOpened = false;
    var loggedOut = false;

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsView(
          fullName: 'Manager User',
          user: 'manager@example.com',
          serverUrl: 'https://restaurant.example.com',
          appVersion: 'v1.2.3 (45)',
          showPrinterSetup: true,
          onPrinterSetup: () => printerOpened = true,
          onLogout: () => loggedOut = true,
        ),
      ),
    );

    await tester.tap(find.text('Windows Print Service'));
    expect(printerOpened, isTrue);

    await tester.ensureVisible(find.text('Log Out'));
    await tester.tap(find.text('Log Out'));
    expect(loggedOut, isTrue);
  });

  testWidgets(
    'cashier retains and surfaces one accepted job while preventing double taps',
    (tester) async {
      final request = Completer<PrintRequestResult>();
      final repository = _FakeWindowsPrintGateway(request: request.future);

      await tester.pumpWidget(_cashierHarness(repository));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(CashierScreen)),
      );

      await tester.tap(find.text('Print Bill'));
      await tester.tap(find.text('Print Bill'));
      await tester.pump();

      expect(repository.requestedInvoices, ['SINV-0001']);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Sending…'))
            .onPressed,
        isNull,
      );

      request.complete(_pendingResult());
      await tester.pumpAndSettle();

      expect(find.text('Print job sent'), findsOneWidget);
      expect(
        find.text('Job ID: 10ba038e-48da-487b-96e8-8d3b99b6d18a'),
        findsOneWidget,
      );
      expect(find.text('Bill printed.'), findsNothing);
      expect(
        container.read(lastAcceptedPrintJobProvider)?.jobId,
        '10ba038e-48da-487b-96e8-8d3b99b6d18a',
      );
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

  testWidgets('shows Windows status and retries only the known accepted job', (
    tester,
  ) async {
    final repository = _FakeWindowsPrintGateway(
      status: const WindowsPrintStatus(
        online: true,
        lastSeen: '2026-09-05 10:11:12',
        pending: 2,
        failed: 3,
      ),
    );

    await tester.pumpWidget(
      _printerHarness(
        repository,
        bootstrap: _bootstrap(
          manager: true,
          canViewPrintStatus: true,
          canRetryPrintJobs: true,
        ),
        initialJobContext: _knownJob(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Online'), findsOneWidget);
    expect(find.text('Last seen: 2026-09-05 10:11:12'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Bluetooth'), findsNothing);
    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.text('10ba038e-48da-487b-96e8-8d3b99b6d18a'), findsOneWidget);
    expect(find.byKey(const Key('failed-print-job-id')), findsNothing);
    expect(find.text('Retry This Job'), findsOneWidget);

    await tester.ensureVisible(find.text('Retry This Job'));
    await tester.tap(find.text('Retry This Job'));
    await tester.pumpAndSettle();

    expect(repository.retriedJobIds, ['10ba038e-48da-487b-96e8-8d3b99b6d18a']);
    expect(repository.statusRequests, greaterThanOrEqualTo(2));
  });

  testWidgets('failed aggregate without a known job gives ERPNext guidance', (
    tester,
  ) async {
    final repository = _FakeWindowsPrintGateway(
      status: const WindowsPrintStatus(
        online: true,
        lastSeen: null,
        pending: 0,
        failed: 2,
      ),
    );

    await tester.pumpWidget(
      _printerHarness(
        repository,
        bootstrap: _bootstrap(
          manager: true,
          canViewPrintStatus: true,
          canRetryPrintJobs: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Retry This Job'), findsNothing);
    expect(find.byKey(const Key('failed-print-job-id')), findsNothing);
    expect(
      find.text(
        'Ask an administrator to open Local Print Job in ERPNext to identify and retry failed jobs.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('retry stays hidden when bootstrap denies retry', (tester) async {
    final repository = _FakeWindowsPrintGateway(
      status: const WindowsPrintStatus(
        online: false,
        lastSeen: null,
        pending: 0,
        failed: 2,
      ),
    );

    await tester.pumpWidget(
      _printerHarness(
        repository,
        bootstrap: _bootstrap(
          cashier: true,
          canViewPrintStatus: true,
          canRetryPrintJobs: false,
        ),
        initialJobContext: _knownJob(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Offline'), findsOneWidget);
    expect(find.text('Retry This Job'), findsNothing);
  });

  testWidgets('test print stays visible when status loading fails', (
    tester,
  ) async {
    final repository = _FakeWindowsPrintGateway(
      statusError: const ApiException('Print status unavailable.'),
    );

    await tester.pumpWidget(
      _printerHarness(
        repository,
        bootstrap: _bootstrap(
          cashier: true,
          canViewPrintStatus: true,
          canRetryPrintJobs: true,
        ),
        initialJobContext: _knownJob(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Print status unavailable.'), findsOneWidget);
    expect(find.text('Retry Status'), findsOneWidget);
    expect(find.text('Retry This Job'), findsOneWidget);
    expect(find.text('Test Cashier Print'), findsOneWidget);

    await tester.ensureVisible(find.text('Test Cashier Print'));
    await tester.tap(find.text('Test Cashier Print'));
    await tester.pumpAndSettle();
    expect(repository.requestedInvoices, ['SINV-0001']);
    expect(find.text('Print job sent'), findsOneWidget);
  });

  testWidgets('test print requires a named submitted invoice context', (
    tester,
  ) async {
    final repository = _FakeWindowsPrintGateway();
    final bootstrap = _bootstrap(cashier: true, canViewPrintStatus: true);

    await tester.pumpWidget(_printerHarness(repository, bootstrap: bootstrap));
    await tester.pumpAndSettle();
    expect(find.text('Test Cashier Print'), findsNothing);

    await tester.pumpWidget(
      _printerHarness(
        repository,
        bootstrap: bootstrap,
        initialJobContext: _knownJob(invoiceDocstatus: 0),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Test Cashier Print'), findsNothing);

    await tester.pumpWidget(
      _printerHarness(
        repository,
        bootstrap: bootstrap,
        initialJobContext: _knownJob(invoiceName: ''),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Test Cashier Print'), findsNothing);
  });

  testWidgets(
    'test-print completion after disposal does not touch dead state',
    (tester) async {
      final request = Completer<PrintRequestResult>();
      final repository = _FakeWindowsPrintGateway(request: request.future);

      await tester.pumpWidget(
        _printerHarness(
          repository,
          bootstrap: _bootstrap(cashier: true, canViewPrintStatus: true),
          initialJobContext: _knownJob(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Test Cashier Print'));
      await tester.tap(find.text('Test Cashier Print'));
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));

      request.complete(_pendingResult());
      await tester.pump();

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('direct screen access is denied before status is requested', (
    tester,
  ) async {
    final repository = _FakeWindowsPrintGateway();

    await tester.pumpWidget(
      _printerHarness(repository, bootstrap: _bootstrap(waiter: true)),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('You are not authorized to view print status.'),
      findsOneWidget,
    );
    expect(find.text('Retry This Job'), findsNothing);
    expect(find.text('Test Cashier Print'), findsNothing);
    expect(repository.statusRequests, 0);
  });

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
      _printerHarness(
        repository,
        bootstrap: _bootstrap(
          manager: true,
          canViewPrintStatus: true,
          canRetryPrintJobs: true,
        ),
        initialJobContext: _knownJob(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Retry This Job'));
    await tester.tap(find.text('Retry This Job'));
    await tester.tap(find.text('Retry This Job'));
    await tester.pump();

    expect(repository.retriedJobIds, hasLength(1));

    retry.completeError(const ApiException('Retry is not allowed.'));
    await tester.pumpAndSettle();

    expect(find.text('Retry is not allowed.'), findsOneWidget);
    expect(repository.statusRequests, greaterThanOrEqualTo(2));
  });

  testWidgets('manager with print-status permission reaches the destination', (
    tester,
  ) async {
    final repository = _FakeWindowsPrintGateway();
    await tester.pumpWidget(
      _routerHarness(
        repository,
        _bootstrap(manager: true, canViewPrintStatus: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Windows Print Service'), findsOneWidget);

    await tester.tap(find.text('Windows Print Service'));
    await tester.pumpAndSettle();
    expect(find.text('Online'), findsOneWidget);
  });

  testWidgets('accepted cashier job survives navigation to printer settings', (
    tester,
  ) async {
    final repository = _FakeWindowsPrintGateway();
    await tester.pumpWidget(
      _routerHarness(
        repository,
        _bootstrap(cashier: true, canViewPrintStatus: true),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Print Bill'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View status'));
    await tester.pumpAndSettle();

    expect(find.text('Last accepted print job'), findsOneWidget);
    expect(find.text('10ba038e-48da-487b-96e8-8d3b99b6d18a'), findsOneWidget);
    expect(find.text('Test Cashier Print'), findsOneWidget);
  });

  testWidgets('waiter without print-status permission is denied the route', (
    tester,
  ) async {
    final repository = _FakeWindowsPrintGateway();
    await tester.pumpWidget(
      _routerHarness(repository, _bootstrap(waiter: true)),
    );
    await tester.pump();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(_RouterTestApp)),
    );

    container.read(routerProvider).go('/printer-settings');
    await tester.pump();

    expect(
      container.read(routerProvider).routeInformationProvider.value.uri.path,
      '/settings',
    );
    expect(find.text('Windows Print Service'), findsNothing);
  });
}

Widget _cashierHarness(WindowsPrintGateway repository) {
  return ProviderScope(
    overrides: [
      authControllerProvider.overrideWith(
        () => _TestAuthController(
          _bootstrap(cashier: true, canViewPrintStatus: true),
        ),
      ),
      windowsPrintRepositoryProvider.overrideWithValue(repository),
      cashierBillingProvider.overrideWith((ref) async => _billing()),
    ],
    child: const MaterialApp(home: CashierScreen()),
  );
}

Widget _printerHarness(
  WindowsPrintGateway repository, {
  required BootstrapModel bootstrap,
  KnownPrintJobContext? initialJobContext,
}) {
  return ProviderScope(
    overrides: [
      authControllerProvider.overrideWith(() => _TestAuthController(bootstrap)),
      windowsPrintRepositoryProvider.overrideWithValue(repository),
    ],
    child: MaterialApp(
      home: PrinterSettingsScreen(initialJobContext: initialJobContext),
    ),
  );
}

Widget _routerHarness(
  WindowsPrintGateway repository,
  BootstrapModel bootstrap,
) {
  return ProviderScope(
    overrides: [
      authControllerProvider.overrideWith(() => _TestAuthController(bootstrap)),
      appVersionProvider.overrideWith((ref) async => 'v1.2.3'),
      windowsPrintRepositoryProvider.overrideWithValue(repository),
      cashierBillingProvider.overrideWith((ref) async => _billing()),
    ],
    child: const _RouterTestApp(),
  );
}

class _RouterTestApp extends ConsumerWidget {
  const _RouterTestApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(routerConfig: ref.watch(routerProvider));
  }
}

PrintRequestResult _pendingResult({
  String jobId = '10ba038e-48da-487b-96e8-8d3b99b6d18a',
}) => PrintRequestResult.fromJson({
  'job_id': jobId,
  'status': 'Pending',
  'is_reprint': false,
});

KnownPrintJobContext _knownJob({
  String invoiceName = 'SINV-0001',
  int invoiceDocstatus = 1,
}) => KnownPrintJobContext(
  invoiceName: invoiceName,
  invoiceDocstatus: invoiceDocstatus,
  request: _pendingResult(),
);

BootstrapModel _bootstrap({
  bool waiter = false,
  bool cashier = false,
  bool manager = false,
  bool canViewPrintStatus = false,
  bool canRetryPrintJobs = false,
}) => BootstrapModel(
  user: 'user@example.com',
  fullName: 'Restaurant User',
  roles: const [],
  permissions: BootstrapPermissions(
    waiter: waiter,
    kitchen: false,
    cashier: cashier,
    manager: manager,
    canRequestCashierPrint: cashier || manager,
    canViewPrintStatus: canViewPrintStatus,
    canRetryPrintJobs: canRetryPrintJobs,
  ),
  company: 'BCN',
  currency: 'MMK',
  sellingPriceList: 'Standard Selling',
  kitchenCounters: const [],
);

CashierBillingResponse _billing() => CashierBillingResponse(
  invoices: [_invoice()],
  modes: const [],
  printerSettings: const CashierPrinterSettings(
    printerIp: '',
    printerPort: 9100,
    paperWidth: '80mm',
  ),
);

CashierInvoice _invoice() => CashierInvoice.fromJson({
  'name': 'SINV-0001',
  'customer': 'Table 1',
  'customer_name': 'Table 1',
  'creation': '2026-09-05 10:00:00',
  'net_total': 1000,
  'total_taxes_and_charges': 0,
  'grand_total': 1000,
  'outstanding_amount': 1000,
  'currency': 'MMK',
  'docstatus': 1,
  'payment_status': 'Unpaid',
  'sales_orders': ['SO-0001'],
  'items': const [],
  'taxes': const [],
  'bill_printed': false,
  'bill_printed_total': 0,
});

class _FakeWindowsPrintGateway implements WindowsPrintGateway {
  _FakeWindowsPrintGateway({
    Future<PrintRequestResult>? request,
    this.requestError,
    Future<void>? retry,
    this.statusError,
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
  final Object? statusError;
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
  Future<WindowsPrintStatus> getStatus() {
    statusRequests += 1;
    final error = statusError;
    if (error != null) return Future.error(error);
    return Future.value(status);
  }

  @override
  Future<void> retryJob(String jobId) {
    retriedJobIds.add(jobId);
    return _retry;
  }
}

class _TestAuthController extends AuthController {
  _TestAuthController(this.bootstrap);

  final BootstrapModel bootstrap;

  @override
  Future<AuthState> build() async => AuthState.authenticated(bootstrap);
}
