import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/presentation/auth_controller.dart';
import '../../cart/domain/cart_controller.dart';
import '../data/tables_repository.dart';
import '../domain/table_models.dart';

final tablesRepositoryProvider = Provider<TablesRepository>(
  (ref) => TablesRepository(ref.watch(apiClientProvider)),
);

final tablesProvider = FutureProvider.family<TablesResponse, String>(
  (ref, serviceType) => ref.watch(tablesRepositoryProvider).getTables(serviceType),
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
        title: Text(bootstrap?.fullName.isNotEmpty == true ? bootstrap!.fullName : 'Waiter'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(tablesProvider(serviceType)),
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Logout',
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'dine_in', label: Text('Dine In'), icon: Icon(Icons.table_restaurant)),
                ButtonSegment(value: 'takeaway', label: Text('Takeaway'), icon: Icon(Icons.takeout_dining)),
              ],
              selected: {serviceType},
              onSelectionChanged: (selection) {
                setState(() => serviceType = selection.first);
              },
            ),
          ),
          Expanded(
            child: tables.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text(error.toString())),
              data: (response) => RefreshIndicator(
                onRefresh: () => ref.refresh(tablesProvider(serviceType).future),
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
                        ref.read(cartProvider.notifier).setOrderContext(
                              customer: table.customer,
                              session: table.session,
                            );
                        context.go('/menu/${Uri.encodeComponent(table.customer)}');
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
              Text(table.customerName, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(table.isOpen ? Icons.circle : Icons.circle_outlined, size: 14),
                  const SizedBox(width: 6),
                  Text(table.isOpen ? (table.sessionStatus ?? 'Open') : 'Available'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
