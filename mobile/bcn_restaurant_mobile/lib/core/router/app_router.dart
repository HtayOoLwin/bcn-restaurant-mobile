import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/auth_controller.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/cart/presentation/cart_screen.dart';
import '../../features/cashier/presentation/cashier_screen.dart';
import '../../features/kitchen/presentation/kitchen_orders_screen.dart';
import '../../features/menu/presentation/menu_screen.dart';
import '../../features/printing/presentation/printer_settings_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/waiter/presentation/waiter_tables_screen.dart';
import '../../features/waiter_progress/presentation/waiter_progress_screen.dart';
import '../../features/waiter_progress/presentation/waiter_ready_screen.dart';

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
      final canKitchen = authState?.bootstrap?.permissions.kitchen == true;
      final canCashier = authState?.bootstrap?.permissions.cashier == true;
      if (!canWaiter && !canKitchen && !canCashier) {
        return state.matchedLocation == '/unsupported' ? null : '/unsupported';
      }

      if (state.matchedLocation == '/login' ||
          state.matchedLocation == '/loading' ||
          state.matchedLocation == '/unsupported') {
        if (canWaiter) return '/tables';
        if (canKitchen) return '/kitchen';
        return '/cashier';
      }

      if (state.matchedLocation.startsWith('/kitchen') && !canKitchen) {
        return canWaiter ? '/tables' : '/cashier';
      }
      if (state.matchedLocation.startsWith('/cashier') && !canCashier) {
        return canWaiter ? '/tables' : '/kitchen';
      }
      if ((state.matchedLocation.startsWith('/tables') ||
              state.matchedLocation.startsWith('/menu') ||
              state.matchedLocation.startsWith('/cart') ||
              state.matchedLocation.startsWith('/waiter/')) &&
          !canWaiter) {
        return canKitchen ? '/kitchen' : '/cashier';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/loading',
        builder: (context, state) =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/tables',
        builder: (context, state) => const WaiterTablesScreen(),
      ),
      GoRoute(
        path: '/waiter/ready',
        builder: (context, state) => const WaiterReadyScreen(),
      ),
      GoRoute(
        path: '/waiter/progress',
        builder: (context, state) => const WaiterProgressScreen(),
      ),
      GoRoute(
        path: '/kitchen',
        builder: (context, state) => const KitchenOrdersScreen(),
      ),
      GoRoute(
        path: '/cashier',
        builder: (context, state) => const CashierScreen(),
      ),
      GoRoute(
        path: '/printer-settings',
        builder: (context, state) => const PrinterSettingsScreen(),
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
      GoRoute(
        path: '/unsupported',
        builder: (context, state) => UnsupportedRoleScreen(
          onLogout: () => ref.read(authControllerProvider.notifier).logout(),
        ),
      ),
    ],
  );
});

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
