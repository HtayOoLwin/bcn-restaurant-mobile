import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/presentation/auth_controller.dart';
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

    return Scaffold(
      appBar: AppBar(
        title: Text(
          bootstrap?.fullName.isNotEmpty == true
              ? bootstrap!.fullName
              : 'Waiter',
        ),
        actions: [
          if (bootstrap?.permissions.cashier == true)
            IconButton(
              tooltip: 'Cashier',
              onPressed: () => context.go('/cashier'),
              icon: const Icon(Icons.point_of_sale),
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
                      onTap: () async {
                        ref
                            .read(cartProvider.notifier)
                            .setOrderContext(
                              customer: table.customer,
                              session: table.session,
                            );

                        await context.push(
                          '/menu/${Uri.encodeComponent(table.customer)}',
                        );

                        ref.invalidate(tablesProvider(serviceType));
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
}

class _TableCard extends StatelessWidget {
  const _TableCard({
    required this.table,
    required this.onTap,
  });

  final RestaurantTableModel table;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = table.isOpen
        ? (table.sessionStatus ?? 'Occupied')
        : 'Available';

    Color cardColor;
    Color statusColor;
    IconData statusIcon;

    switch (status.toLowerCase()) {
      case 'occupied':
        cardColor = Colors.red.shade50;
        statusColor = Colors.red.shade800;
        statusIcon = Icons.restaurant;
        break;

      case 'billing':
        cardColor = Colors.blue.shade50;
        statusColor = Colors.blue.shade700;
        statusIcon = Icons.point_of_sale;
        break;

      case 'available':
      default:
        cardColor = Colors.green.shade50;
        statusColor = Colors.green.shade700;
        statusIcon = Icons.check_circle_outline;
        break;
    }

    return Card(
      color: cardColor,
      elevation: 2,
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
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    statusIcon,
                    size: 16,
                    color: statusColor,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    status,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              if (table.isOpen &&
                  table.session != null &&
                  table.session!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  table.session!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
