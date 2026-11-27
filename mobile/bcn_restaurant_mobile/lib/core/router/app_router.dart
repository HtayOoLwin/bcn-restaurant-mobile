import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/auth_controller.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/cart/presentation/cart_screen.dart';
import '../../features/cart/domain/cart_controller.dart';
import '../../features/cashier/presentation/cashier_screen.dart';
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
        child: ListTile(
          leading: Icon(icon, size: 22),
          title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          selected: selected,
          selectedTileColor: const Color(0xFF397FBB),
          selectedColor: Colors.white,
          iconColor: Colors.white,
          textColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          onTap: () => navigate(destination),
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
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 4, 10, 8),
                      child: Row(children: [
                        const Expanded(child: Text('Restaurant POS', style: TextStyle(color: Colors.white70))),
                        IconButton(
                          tooltip: 'Settings',
                          isSelected: path == '/settings',
                          color: Colors.white,
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
