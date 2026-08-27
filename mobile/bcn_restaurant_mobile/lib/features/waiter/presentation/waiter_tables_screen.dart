import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/presentation/auth_controller.dart';
import '../../notifications/presentation/mobile_notification_watcher.dart';
import '../../kitchen/presentation/kitchen_notification_badge.dart';
import '../../../core/widgets/operational_refresh_indicator.dart';
import '../../cart/domain/cart_controller.dart';
import '../data/tables_repository.dart';
import '../domain/table_models.dart';

final tablesRepositoryProvider = Provider<TablesRepository>(
  (ref) => TablesRepository(ref.watch(apiClientProvider)),
);

final tablesProvider = FutureProvider.family<TablesResponse, String>(
  (ref, serviceType) =>
      ref.watch(tablesRepositoryProvider).getTables(serviceType),
);

class WaiterTablesScreen extends ConsumerStatefulWidget {
  const WaiterTablesScreen({super.key});

  @override
  ConsumerState<WaiterTablesScreen> createState() => _WaiterTablesScreenState();
}

class _WaiterTablesScreenState extends ConsumerState<WaiterTablesScreen> {
  String serviceType = 'dine_in';

  @override
  Widget build(BuildContext context) {
    final bootstrap = ref.watch(authControllerProvider).asData?.value.bootstrap;
    final tables = ref.watch(tablesProvider(serviceType));
    final notificationCount =
        ref.watch(mobileNotificationsProvider).asData?.value.length ?? 0;
    final kitchenNewOrderCount =
        ref.watch(kitchenNewOrderCountProvider).asData?.value ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          bootstrap?.fullName.isNotEmpty == true
              ? bootstrap!.fullName
              : 'Waiter',
        ),
        actions: [
          if (bootstrap?.permissions.kitchen == true)
            IconButton(
              tooltip: 'Kitchen',
              onPressed: () => context.go('/kitchen'),
              icon: kitchenNewOrderCount > 0
                  ? Badge.count(
                      count: kitchenNewOrderCount,
                      child: const Icon(Icons.soup_kitchen),
                    )
                  : const Icon(Icons.soup_kitchen),
            ),
          if (bootstrap?.permissions.cashier == true)
            IconButton(
              tooltip: 'Cashier',
              onPressed: () => context.go('/cashier'),
              icon: const Icon(Icons.point_of_sale),
            ),
          IconButton(
            tooltip: 'Ready to Serve',
            onPressed: _openReadyToServe,
            icon: notificationCount > 0
                ? Badge.count(
                    count: notificationCount,
                    child: const Icon(Icons.room_service),
                  )
                : const Icon(Icons.room_service),
          ),
          IconButton(
            tooltip: 'Order Progress',
            onPressed: () => context.push('/waiter/progress'),
            icon: const Icon(Icons.pending_actions),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(tablesProvider(serviceType)),
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: () => context.push('/settings'),
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'dine_in',
                  label: Text('Dine In'),
                  icon: Icon(Icons.table_restaurant),
                ),
                ButtonSegment(
                  value: 'takeaway',
                  label: Text('Takeaway'),
                  icon: Icon(Icons.takeout_dining),
                ),
              ],
              selected: {serviceType},
              onSelectionChanged: (selection) {
                setState(() => serviceType = selection.first);
              },
            ),
          ),
          OperationalRefreshIndicator(
            onRefresh: () => ref.invalidate(tablesProvider(serviceType)),
          ),
          Expanded(
            child: tables.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text(error.toString())),
              data: (response) => RefreshIndicator(
                onRefresh: () =>
                    ref.refresh(tablesProvider(serviceType).future),
                child: GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 220,
                    childAspectRatio: 1.5,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: response.tables.length,
                  itemBuilder: (context, index) {
                    final table = response.tables[index];
                    return _TableCard(
                      table: table,
                      onTap: () {
                        ref
                            .read(cartProvider.notifier)
                            .setOrderContext(
                              customer: table.customer,
                              session: table.session,
                            );
                        context.push(
                          '/menu/${Uri.encodeComponent(table.customer)}',
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openReadyToServe() async {
    final notifications = ref.read(mobileNotificationsProvider).asData?.value;
    if (notifications?.isNotEmpty == true) {
      try {
        await ref.read(mobileNotificationsRepositoryProvider).markAllRead();
        ref.invalidate(mobileNotificationsProvider);
      } catch (_) {
        // Opening Ready to Serve should not be blocked by notification cleanup.
      }
    }
    if (mounted) {
      context.push('/waiter/ready');
    }
  }
}

class _TableCard extends StatelessWidget {
  const _TableCard({required this.table, required this.onTap});

  final RestaurantTableModel table;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                table.customerName,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    table.isOpen ? Icons.circle : Icons.circle_outlined,
                    size: 14,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    table.isOpen
                        ? (table.sessionStatus ?? 'Open')
                        : 'Available',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
