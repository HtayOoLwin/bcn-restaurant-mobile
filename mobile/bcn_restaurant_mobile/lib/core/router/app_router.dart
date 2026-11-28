import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../network/api_exception.dart';
import '../../features/orders/presentation/offline_orders_screen.dart';
import '../../features/orders/data/offline_sync_service.dart';
import '../../features/waiter_progress/presentation/waiter_ready_screen.dart';
import '../../features/auth/presentation/auth_controller.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/cart/presentation/cart_screen.dart';
import '../../features/cart/domain/cart_controller.dart';
import '../../features/cashier/presentation/cashier_screen.dart';
import '../../features/cashier/data/offline_payment_service.dart';
import '../../features/cashier/presentation/cashier_daily_report_screen.dart';
import '../../features/cashier/presentation/cashier_sales_summary_screen.dart';
import '../../features/credit/presentation/credit_customers_screen.dart';
import '../../features/menu/presentation/menu_screen.dart';
import '../../features/room/presentation/room_timer_demo_screen.dart';
import '../../features/printing/domain/windows_print_status.dart';
import '../../features/printing/presentation/printer_settings_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/waiter/presentation/waiter_tables_screen.dart';
import '../../features/waiter_progress/presentation/waiter_progress_screen.dart';

enum _ServerStatus { online, offline, sessionExpired, unavailable }

final _serverStatusProvider = StreamProvider.autoDispose<_ServerStatus>((ref) async* {
  final api = ref.watch(apiClientProvider);
  final expectedUser = ref.watch(authControllerProvider).asData?.value.bootstrap?.user;
  var authFailures = 0;
  while (true) {
    var status = _ServerStatus.unavailable;
    try {
      final user = await api.getMethod('frappe.auth.get_logged_user')
          .timeout(const Duration(seconds: 8));
      if (user is String && user.isNotEmpty && user != 'Guest' &&
          user == expectedUser) {
        authFailures = 0;
        status = _ServerStatus.online;
      } else if (user == 'Guest' || (user is String && user.isNotEmpty && user != expectedUser)) {
        authFailures++;
        status = authFailures >= 2 ? _ServerStatus.sessionExpired : _ServerStatus.unavailable;
      } else {
        authFailures = 0;
      }
    } on TimeoutException {
      authFailures = 0;
      status = _ServerStatus.offline;
    } on ApiException catch (error) {
      if (error.statusCode == null) {
        authFailures = 0;
        status = _ServerStatus.offline;
      } else if (error.statusCode == 401 || error.statusCode == 403) {
        // A single forbidden response during reconnect is not proof of expiry.
        // Verify using a fresh bootstrap response, never the offline snapshot.
        try {
          final data = await api.getMethod('bcn_mobile_bootstrap')
              .timeout(const Duration(seconds: 8));
          if (data is Map && data['_offline_cached'] != true &&
              expectedUser != null && data['user'] == expectedUser) {
            authFailures = 0;
            status = _ServerStatus.online;
          } else {
            authFailures = 0;
          }
        } on ApiException catch (second) {
          if (error.statusCode == 401 && second.statusCode == 401) {
            authFailures++;
            status = authFailures >= 2 ? _ServerStatus.sessionExpired : _ServerStatus.unavailable;
          } else {
            authFailures = 0;
            status = second.statusCode == null ? _ServerStatus.offline : _ServerStatus.unavailable;
          }
        } on TimeoutException {
          authFailures = 0;
          status = _ServerStatus.offline;
        } catch (_) {
          authFailures = 0;
        }
      } else {
        authFailures = 0;
      }
    } catch (_) {
      authFailures = 0;
    }
    yield status;
    await Future<void>.delayed(const Duration(seconds: 5));
  }
});

final _desktopPackageInfoProvider = FutureProvider<PackageInfo>((ref) => PackageInfo.fromPlatform());

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authControllerProvider);
  final authState = auth.asData?.value;

  return GoRouter(
    initialLocation: '/loading',
    redirect: (context, state) {
      if (auth.isLoading) {
        return state.matchedLocation == '/loading' ? null : '/loading';
      }

      final authenticated = authState?.isAuthenticated == true;
      if (!authenticated) {
        return state.matchedLocation == '/login' ? null : '/login';
      }

      final canWaiter = authState?.bootstrap?.permissions.waiter == true;
      final canCashier = authState?.bootstrap?.permissions.cashier == true;
      final canViewPrintStatus =
          authState?.bootstrap?.permissions.canViewPrintStatus == true;

      String defaultLocation() {
        if (canWaiter) return '/tables';
        if (canCashier) return '/cashier';
        if (canViewPrintStatus) return '/settings';
        return '/unsupported';
      }

      if (!canWaiter && !canCashier && !canViewPrintStatus) {
        return state.matchedLocation == '/unsupported' ? null : '/unsupported';
      }

      if (state.matchedLocation == '/login' ||
          state.matchedLocation == '/loading' ||
          state.matchedLocation == '/unsupported') {
        return defaultLocation();
      }

      if (state.matchedLocation.startsWith('/cashier') && !canCashier) {
        return defaultLocation();
      }
      if ((state.matchedLocation.startsWith('/tables') ||
              state.matchedLocation.startsWith('/menu') ||
              state.matchedLocation.startsWith('/cart') ||
              state.matchedLocation.startsWith('/waiter-progress')) &&
          !canWaiter) {
        return defaultLocation();
      }
      if (state.matchedLocation.startsWith('/printer-settings') &&
          !canViewPrintStatus) {
        return '/settings';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/loading',
        builder: (context, state) => const BcnLoadingScreen(),
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      ShellRoute(
        builder: (context, state, child) => _DesktopShell(path: state.uri.path, child: child),
        routes: [
      GoRoute(
        path: '/tables',
        builder: (context, state) => const WaiterTablesScreen(),
      ),
      GoRoute(
        path: '/waiter-progress',
        builder: (context, state) => const WaiterProgressScreen(),
      ),
      GoRoute(
        path: '/cashier',
        builder: (context, state) => const CashierScreen(),
      ),
      GoRoute(
        path: '/cashier/credits',
        builder: (context, state) => const CreditCustomersScreen(),
      ),
      GoRoute(
        path: '/cashier/reports/daily',
        builder: (context, state) => CashierDailyReportScreen(
          repository: ref.read(cashierRepositoryProvider),
        ),
      ),
      GoRoute(
        path: '/cashier/reports/items',
        builder: (context, state) => CashierSalesSummaryScreen(
          repository: ref.read(cashierRepositoryProvider),
        ),
      ),
      GoRoute(
        path: '/printer-settings',
        builder: (context, state) => PrinterSettingsScreen(
          initialJobContext: state.extra is KnownPrintJobContext
              ? state.extra as KnownPrintJobContext
              : null,
        ),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/menu/:customer',
        builder: (context, state) => MenuScreen(
          customer: Uri.decodeComponent(state.pathParameters['customer'] ?? ''),
        ),
      ),
      GoRoute(path: '/cart', builder: (context, state) => const CartScreen()),
      GoRoute(path: '/room-timer-demo', builder: (context, state) => const RoomTimerDemoScreen()),
        ],
      ),
      GoRoute(
        path: '/unsupported',
        builder: (context, state) => UnsupportedRoleScreen(
          onLogout: () => ref.read(authControllerProvider.notifier).logout(),
        ),
      ),
    ],
  );
});

class BcnLoadingScreen extends StatelessWidget {
  const BcnLoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFFF8F5F2),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 180,
                height: 180,
                child: Image(
                  image: AssetImage('assets/images/OurCityLogo.png'),
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
              ),
              SizedBox(height: 28),
              SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 2.6,
                  color: Color(0xFF6B3A14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class UnsupportedRoleScreen extends StatelessWidget {
  const UnsupportedRoleScreen({super.key, required this.onLogout});

  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('BCN Restaurant')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.construction, size: 64),
              const SizedBox(height: 16),
              const Text(
                'This role is recognized, but its mobile screen is planned for a later phase.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onLogout, child: const Text('Logout')),
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopShell extends ConsumerWidget {
  const _DesktopShell({required this.path, required this.child});
  final String path;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (Theme.of(context).platform != TargetPlatform.windows ||
        MediaQuery.sizeOf(context).width < 900) {
      return child;
    }
    final bootstrap = ref.watch(authControllerProvider).asData?.value.bootstrap;
    final permissions = bootstrap?.permissions;
    Future<void> navigate(String destination) async {
      if (path == destination) return;
      if ((path.startsWith('/menu/') || path == '/cart') &&
          ref.read(cartProvider).lines.isNotEmpty) {
        final leave = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Unsaved order'),
            content: const Text('Leave this order and discard the unsaved cart?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Stay')),
              FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Discard')),
            ],
          ),
        );
        if (leave != true || !context.mounted) return;
        ref.read(cartProvider.notifier).clear();
      }
      if (context.mounted) context.go(destination);
    }
    Widget nav(IconData icon, String title, String destination, bool selected) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Material(
          color: selected ? const Color(0xFF397FBB) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => navigate(destination),
            hoverColor: Colors.white.withValues(alpha: 0.08),
            child: Row(
              children: [
                SizedBox(
                  width: 4,
                  height: 44,
                  child: ColoredBox(
                    color: selected ? Colors.white : Colors.transparent,
                  ),
                ),
                const SizedBox(width: 12),
                Icon(icon, size: 22, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(title, style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  )),
                ),
                if (selected)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Icon(Icons.chevron_right, color: Colors.white, size: 16),
                  ),
              ],
            ),
          ),
        ),
      );
    }
    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: 220,
            child: ColoredBox(
              color: const Color(0xFF155484),
              child: SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(children: [
                        const Icon(Icons.restaurant, color: Colors.white, size: 26),
                        const SizedBox(width: 10),
                        Expanded(child: Text(bootstrap?.company ?? 'Restaurant',
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800))),
                      ]),
                    ),
                    const Divider(color: Colors.white24, height: 1),
                    ListTile(
                      leading: const Icon(Icons.account_circle_outlined, color: Colors.white),
                      title: Text(bootstrap?.fullName ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                      subtitle: Text(permissions?.waiter == true ? 'Waiter' : permissions?.cashier == true ? 'Cashier' : 'User',
                        style: const TextStyle(color: Colors.white70)),
                    ),
                    const Divider(color: Colors.white24, height: 1),
                    Expanded(child: ListView(
                      padding: const EdgeInsets.all(8),
                      children: [
                        if (permissions?.waiter == true) ...[
                          nav(Icons.table_restaurant_outlined, 'Tables', '/tables', path == '/tables' || path.startsWith('/menu/') || path == '/cart'),
                          nav(Icons.receipt_long_outlined, 'Orders', '/waiter-progress', path == '/waiter-progress'),
                        ],
                        if (permissions?.cashier == true) ...[
                          nav(Icons.point_of_sale_outlined, 'Cashier', '/cashier', path == '/cashier'),
                          nav(Icons.people_outline, 'Credit Customers', '/cashier/credits', path == '/cashier/credits'),
                          const Padding(
                            padding: EdgeInsets.fromLTRB(16, 12, 8, 6),
                            child: Text('REPORTS', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w700)),
                          ),
                          nav(Icons.calendar_today_outlined, 'Daily Sales Report', '/cashier/reports/daily', path == '/cashier/reports/daily'),
                          nav(Icons.bar_chart_outlined, 'Sales by Item', '/cashier/reports/items', path == '/cashier/reports/items'),
                        ],
                        if (permissions?.canViewPrintStatus == true)
                          nav(Icons.print_outlined, 'Printer Settings', '/printer-settings', path == '/printer-settings'),
                      ],
                    )),
                    const Divider(color: Colors.white24),
                    const _ConnectionStatusFooter(),
                    const Divider(color: Colors.white24, height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 4, 10, 8),
                      child: Row(children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('Restaurant POS', style: TextStyle(color: Colors.white70)),
                              const SizedBox(height: 4),
                              ref.watch(_desktopPackageInfoProvider).when(
                                data: (info) => Text(
                                  'Version ${info.version}${info.buildNumber.isEmpty ? '' : ' (${info.buildNumber})'}',
                                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                                ),
                                loading: () => const Text('Version …', style: TextStyle(color: Colors.white60, fontSize: 11)),
                                error: (_, _) => const Text('Version unavailable', style: TextStyle(color: Colors.white60, fontSize: 11)),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Settings',
                          isSelected: path == '/settings',
                          color: Colors.white,
                          style: IconButton.styleFrom(
                            backgroundColor: path == '/settings' ? const Color(0xFF397FBB) : Colors.transparent,
                          ),
                          selectedIcon: const Icon(Icons.settings, color: Colors.white),
                          icon: const Icon(Icons.settings_outlined),
                          onPressed: () => navigate('/settings'),
                        ),
                      ]),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _ConnectionStatusFooter extends ConsumerStatefulWidget {
  const _ConnectionStatusFooter();

  @override
  ConsumerState<_ConnectionStatusFooter> createState() => _ConnectionStatusFooterState();
}

class _ConnectionStatusFooterState extends ConsumerState<_ConnectionStatusFooter> {
  bool _autoSync = true;
  bool _autoScheduled = false;
  bool _dispatching = false;

  Future<void> _runSync({bool manual = false}) async {
    if (_dispatching || !mounted) return;
    _dispatching = true;
    try {
      final permissions = ref.read(authControllerProvider).asData?.value.bootstrap?.permissions;
      final api = ref.read(apiClientProvider);
      final orders = ref.read(offlineSyncProvider);
      final payments = ref.read(offlinePaymentProvider);
      if (orders.running || payments.running) return;
      if (permissions?.waiter == true && (manual || orders.errors.isEmpty) &&
          (await api.pendingOrders()).isNotEmpty) {
        if (!mounted) return;
        await ref.read(offlineSyncProvider.notifier).sync();
      }
      if (!mounted) return;
      // Never settle an offline bill before its queued orders have synced.
      if (permissions?.cashier == true && (manual || payments.error == null) &&
          (await api.pendingOrders()).isEmpty && (await api.pendingPayments()).isNotEmpty) {
        if (!mounted) return;
        await ref.read(offlinePaymentProvider.notifier).sync();
      }
    } catch (error) {
      if (mounted && manual) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      _dispatching = false;
    }
  }

  @override
  void initState() {
    super.initState();
    _maybeAutoSync();
  }

  void _maybeAutoSync() {
    if (!_autoSync || _autoScheduled) return;
    _autoScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoScheduled = false;
      if (!mounted || !_autoSync) return;
      final online = ref.read(_serverStatusProvider).asData?.value == _ServerStatus.online;
      final orderCount = ref.read(pendingOrderCountProvider).asData?.value ?? 0;
      final paymentCount = ref.read(pendingPaymentCountProvider).asData?.value ?? 0;
      if (online && (orderCount > 0 || paymentCount > 0)) {
        unawaited(_runSync());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(_serverStatusProvider).asData?.value;
    final sync = ref.watch(offlineSyncProvider);
    final pending = ref.watch(pendingOrderCountProvider);
    final count = pending.asData?.value ?? 0;
    final permissions = ref.watch(authControllerProvider).asData?.value.bootstrap?.permissions;
    final canSync = permissions?.waiter == true || permissions?.cashier == true;
    final paymentSync = ref.watch(offlinePaymentProvider);
    final paymentCount = ref.watch(pendingPaymentCountProvider).asData?.value ?? 0;
    final syncing = sync.running || paymentSync.running;
    ref.listen(pendingPaymentCountProvider, (_, next) {
      if ((next.asData?.value ?? 0) > 0) _maybeAutoSync();
    });
    ref.listen(offlinePaymentProvider, (previous, next) {
      if (previous?.running == true && !next.running) {
        ref.invalidate(cashierBillingProvider);
        ref.invalidate(tablesProvider);
        ref.invalidate(waiterProgressProvider);
        ref.invalidate(waiterReadyProvider);
      }
    });
    ref.listen(offlineSyncProvider, (previous, next) {
      if (previous?.running == true && !next.running) {
        ref.invalidate(pendingOrderCountProvider);
        ref.invalidate(tablesProvider);
        ref.invalidate(waiterProgressProvider);
        ref.invalidate(waiterReadyProvider);
        ref.invalidate(cashierBillingProvider);
      }
    });
    ref.listen(_serverStatusProvider, (previous, next) {
      if (previous?.asData?.value != _ServerStatus.online &&
          next.asData?.value == _ServerStatus.online) {
        _maybeAutoSync();
      }
    });
    ref.listen(pendingOrderCountProvider, (_, next) {
      if ((next.asData?.value ?? 0) > 0) _maybeAutoSync();
    });
    final (label, detail, icon, color) = switch (status) {
      _ServerStatus.online => ('Online Mode', 'ERPNext connected', Icons.wifi, const Color(0xFF86EFAC)),
      _ServerStatus.offline => ('Offline Mode', 'ERPNext unreachable', Icons.wifi_off, const Color(0xFFFF7777)),
      _ServerStatus.sessionExpired => ('Session expired', 'Please sign in again', Icons.lock_outline, const Color(0xFFFFC66D)),
      _ServerStatus.unavailable => ('Checking session', 'Retrying ERPNext connection', Icons.error_outline, const Color(0xFFFF7777)),
      null => ('Checking connection', 'Checking ERPNext...', Icons.sync, Colors.white70),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 13))),
          ]),
          const SizedBox(height: 4),
          Text(detail, style: const TextStyle(color: Colors.white70, fontSize: 11)),
          const SizedBox(height: 4),
          pending.when(
            data: (count) => InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => const OfflineOrdersScreen(),
              )),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(children: [
                  Icon(Icons.receipt_long_outlined, size: 17, color: count > 0 ? const Color(0xFFFF7777) : Colors.white70),
                  const SizedBox(width: 6),
                  Expanded(child: Text('Pending orders: $count', style: TextStyle(
                    color: count > 0 ? const Color(0xFFFF7777) : Colors.white70, fontSize: 12, fontWeight: FontWeight.w700))),
                  const Icon(Icons.chevron_right, size: 18, color: Colors.white70),
                ]),
              ),
            ),
            loading: () => const Text('Pending orders: …', style: TextStyle(color: Colors.white70, fontSize: 12)),
            error: (_, _) => const Text('Pending orders unavailable', style: TextStyle(color: Colors.white70, fontSize: 12)),
          ),
          if (permissions?.cashier == true)
            Text('Pending payments: $paymentCount', style: TextStyle(
              color: paymentCount > 0 ? const Color(0xFFFFC66D) : Colors.white70,
              fontSize: 12, fontWeight: FontWeight.w700)),
          if (canSync && (count > 0 || paymentCount > 0 || syncing)) ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF15803D),
                  foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 8)),
                onPressed: status == _ServerStatus.online && !syncing && (count > 0 || paymentCount > 0)
                    ? () => unawaited(_runSync(manual: true))
                    : null,
                icon: syncing
                    ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.sync, size: 17),
                label: Text(syncing ? 'Syncing…' : 'Sync Now'),
              ),
            ),
          ],
          if (canSync)
            Row(children: [
              Expanded(child: Text(_autoSync ? 'Auto Sync: On' : 'Auto Sync: Off',
                style: TextStyle(
                  color: _autoSync ? const Color(0xFF86EFAC) : Colors.white70,
                  fontSize: 11, fontWeight: FontWeight.w700))),
              SizedBox(height: 28, child: Switch(
                activeThumbColor: Colors.white,
                activeTrackColor: const Color(0xFF16A34A),
                inactiveThumbColor: Colors.white70,
                inactiveTrackColor: const Color(0xFF64748B),
                value: _autoSync,
                onChanged: syncing ? null : (value) {
                  setState(() => _autoSync = value);
                  if (value) _maybeAutoSync();
                },
              )),
            ]),
          if (paymentSync.error != null)
            Tooltip(message: paymentSync.error!, child: Text('Payment needs review: ${paymentSync.error}',
              maxLines: 3, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFFFF7777), fontSize: 11)))
          else if (paymentSync.completed > 0 && !paymentSync.running)
            Text('${paymentSync.completed} payment(s) synced', style: const TextStyle(color: Color(0xFF86EFAC), fontSize: 11)),
          if (sync.errors.isNotEmpty)
            Tooltip(
              message: sync.errors.values.first,
              child: Text('Sync needs review: ${sync.errors.values.first}',
                maxLines: 3, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFFFF7777), fontSize: 10)),
            )
          else if (sync.completed > 0 && !sync.running)
            Text('${sync.completed} order(s) synced', style: const TextStyle(color: Color(0xFF86EFAC), fontSize: 11)),
          if (status == _ServerStatus.offline)
            const Text('Local orders / eligible cash · no printing', style: TextStyle(color: Colors.white70, fontSize: 10)),
        ],
      ),
    );
  }
}
