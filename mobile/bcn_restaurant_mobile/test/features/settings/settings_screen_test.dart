import 'dart:async';

import 'package:bcn_restaurant_mobile/core/network/api_exception.dart';
import 'package:bcn_restaurant_mobile/core/router/app_router.dart';
import 'package:bcn_restaurant_mobile/features/auth/domain/auth_state.dart';
import 'package:bcn_restaurant_mobile/features/auth/presentation/auth_controller.dart';
import 'package:bcn_restaurant_mobile/features/bootstrap/domain/bootstrap_model.dart';
import 'package:bcn_restaurant_mobile/features/cashier/domain/cashier_models.dart';
import 'package:bcn_restaurant_mobile/features/cashier/presentation/cashier_screen.dart';
import 'package:bcn_restaurant_mobile/features/notifications/domain/mobile_notification.dart';
import 'package:bcn_restaurant_mobile/features/notifications/presentation/mobile_notification_watcher.dart';
import 'package:bcn_restaurant_mobile/features/printing/data/windows_print_repository.dart';
import 'package:bcn_restaurant_mobile/features/printing/domain/cashier_bill_print_result.dart';
import 'package:bcn_restaurant_mobile/features/printing/presentation/printer_settings_screen.dart';
import 'package:bcn_restaurant_mobile/features/settings/presentation/settings_screen.dart';
import 'package:bcn_restaurant_mobile/features/waiter/domain/table_models.dart';
import 'package:bcn_restaurant_mobile/features/waiter/presentation/waiter_tables_screen.dart';
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
    'cashier sends one Sales Order print request while preventing double taps',
    (tester) async {
      final request = Completer<CashierBillPrintResult>();
      final repository = _FakeWindowsPrintGateway(request: request.future);

      await tester.pumpWidget(_cashierHarness(repository));
      await tester.pumpAndSettle();
      await _expandCashierBill(tester);

      await tester.tap(find.text('Reprint Bill'));
      await tester.tap(find.text('Reprint Bill'));
      await tester.pump();

      expect(repository.requestedSalesOrders, ['SO-0001']);
      expect(repository.requestIds, hasLength(1));
      expect(repository.requestIds.single, isNotEmpty);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Sending…'))
            .onPressed,
        isNull,
      );

      request.complete(_pendingResult());
      await tester.pumpAndSettle();

      expect(find.text('Print job sent · PRINT-JOB-0001'), findsOneWidget);
    },
  );

  testWidgets('cashier keeps a print API error visible', (tester) async {
    final repository = _FakeWindowsPrintGateway(
      requestError: const ApiException('No cashier printer configured.'),
    );

    await tester.pumpWidget(_cashierHarness(repository));
    await tester.pumpAndSettle();
    await _expandCashierBill(tester);
    await tester.tap(find.text('Reprint Bill'));
    await tester.pumpAndSettle();

    expect(find.text('No cashier printer configured.'), findsOneWidget);
  });

  testWidgets('cashier print completion after disposal does not touch dead state', (
    tester,
  ) async {
    final request = Completer<CashierBillPrintResult>();
    final repository = _FakeWindowsPrintGateway(request: request.future);

    await tester.pumpWidget(_cashierHarness(repository));
    await tester.pumpAndSettle();
    await _expandCashierBill(tester);
    await tester.tap(find.text('Reprint Bill'));
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));

    request.complete(_pendingResult());
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('printer screen describes the Windows polling client', (
    tester,
  ) async {
    await tester.pumpWidget(
      _printerHarness(
        bootstrap: _bootstrap(manager: true, canViewPrintStatus: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Windows Printer Client'), findsOneWidget);
    expect(
      find.text(
        'The Windows printer client polls OurCity for queued print jobs. Mobile no longer retries or monitors printer jobs directly.',
      ),
      findsOneWidget,
    );
    expect(find.text('Print and reprint bills from the Cashier screen.'), findsOneWidget);
    expect(find.text('Retry This Job'), findsNothing);
    expect(find.text('Online'), findsNothing);
  });

  testWidgets('printer screen denies users without print permission', (
    tester,
  ) async {
    await tester.pumpWidget(_printerHarness(bootstrap: _bootstrap(waiter: true)));
    await tester.pumpAndSettle();

    expect(
      find.text('You are not authorized to view printer information.'),
      findsOneWidget,
    );
    expect(find.text('Windows Printer Client'), findsNothing);
  });

  testWidgets('manager with print permission reaches printer information', (
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
    expect(find.text('Windows Printer Client'), findsOneWidget);
  });

  testWidgets('waiter without print permission is denied the printer route', (
    tester,
  ) async {
    final repository = _FakeWindowsPrintGateway();
    await tester.pumpWidget(
      _routerHarness(repository, _bootstrap(waiter: true)),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(_RouterTestApp)),
    );

    container.read(routerProvider).go('/printer-settings');
    await tester.pumpAndSettle();

    expect(
      container.read(routerProvider).routeInformationProvider.value.uri.path,
      '/settings',
    );
    expect(find.text('Windows Printer Client'), findsNothing);
  });
}


Future<void> _expandCashierBill(WidgetTester tester) async {
  await tester.tap(find.text('Table 1'));
  await tester.pumpAndSettle();
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

Widget _printerHarness({required BootstrapModel bootstrap}) {
  return ProviderScope(
    overrides: [
      authControllerProvider.overrideWith(() => _TestAuthController(bootstrap)),
    ],
    child: const MaterialApp(home: PrinterSettingsScreen()),
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
      tablesProvider.overrideWith(
        (ref, serviceType) async => TablesResponse(
          serviceType: serviceType,
          customerGroup: '',
          tables: const [],
        ),
      ),
      mobileNotificationsProvider.overrideWith(
        (ref) async => const <MobileNotification>[],
      ),
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

CashierBillPrintResult _pendingResult() => const CashierBillPrintResult(
  salesOrder: 'SO-0001',
  requestId: 'cashier-test-request',
  printJob: 'PRINT-JOB-0001',
  status: 'Pending',
  isReprint: true,
  duplicate: false,
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
  bills: [_bill()],
  modes: const [],
);

CashierBill _bill() => CashierBill.fromJson({
  'sales_order': 'SO-0001',
  'customer': 'Table 1',
  'customer_name': 'Table 1',
  'creation': '2026-09-08 10:00:00',
  'net_total': 1000,
  'total_taxes_and_charges': 0,
  'grand_total': 1000,
  'currency': 'MMK',
  'restaurant_status': 'Billing',
  'last_print_status': 'Printed',
  'last_print_job': 'PRINT-JOB-OLD',
  'items': const [],
  'taxes': const [],
});

class _FakeWindowsPrintGateway implements WindowsPrintGateway {
  _FakeWindowsPrintGateway({
    Future<CashierBillPrintResult>? request,
    this.requestError,
  }) : _request = request ?? Future.value(_pendingResult());

  final Future<CashierBillPrintResult> _request;
  final Object? requestError;
  final List<String> requestedSalesOrders = [];
  final List<String> requestIds = [];

  @override
  Future<CashierBillPrintResult> requestCashierBill({
    required String salesOrder,
    required String requestId,
  }) {
    requestedSalesOrders.add(salesOrder);
    requestIds.add(requestId);
    final error = requestError;
    if (error != null) return Future.error(error);
    return _request;
  }
}

class _TestAuthController extends AuthController {
  _TestAuthController(this.bootstrap);

  final BootstrapModel bootstrap;

  @override
  Future<AuthState> build() async => AuthState.authenticated(bootstrap);
}
