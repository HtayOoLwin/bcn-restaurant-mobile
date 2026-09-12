import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/presentation/auth_controller.dart';
import '../../../core/search/order_search.dart';
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

int waiterTableColumnCount(double width) {
  if (width < 340) return 2;
  if (width < 700) return 3;
  if (width < 1000) return 4;
  return 5;
}

class WaiterTablesScreen extends ConsumerStatefulWidget {
  const WaiterTablesScreen({super.key});

  @override
  ConsumerState<WaiterTablesScreen> createState() => _WaiterTablesScreenState();
}

class _WaiterTablesScreenState extends ConsumerState<WaiterTablesScreen> {
  String serviceType = 'dine_in';
  String _searchQuery = '';
  final _searchController = TextEditingController();
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();

    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;

      final current = ref.read(tablesProvider(serviceType));
      if (current.isLoading) return;

      ref.invalidate(tablesProvider(serviceType));
    });
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

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
          IconButton(
            tooltip: 'Order Progress',
            onPressed: () => context.push('/waiter-progress'),
            icon: const Icon(Icons.receipt_long),
          ),
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
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ChoiceChip(
                    selected: serviceType == 'dine_in',
                    avatar: const Icon(Icons.groups_2_outlined, size: 18),
                    label: const Text('Dine In'),
                    labelStyle: const TextStyle(fontWeight: FontWeight.w600),
                    onSelected: (_) {
                      if (serviceType == 'dine_in') return;
                      setState(() => serviceType = 'dine_in');
                    },
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    selected: serviceType == 'takeaway',
                    avatar: const Icon(Icons.takeout_dining, size: 18),
                    label: const Text('Takeaway'),
                    labelStyle: const TextStyle(fontWeight: FontWeight.w600),
                    onSelected: (_) {
                      if (serviceType == 'takeaway') return;
                      setState(() => serviceType = 'takeaway');
                    },
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search table, customer, or order',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      ),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (value) {
                setState(() => _searchQuery = value);
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
              data: (response) {
                final filteredTables = response.tables.where((table) {
                  final session = table.session;
                  return matchesOrderSearch(
                    queryText: _searchQuery,
                    tableName: table.customerName,
                    orderNumbers: [
                      if (session != null && session.isNotEmpty) session,
                    ],
                    searchTerms: [table.customer],
                  );
                }).toList();

                return RefreshIndicator(
                  onRefresh: () =>
                      ref.refresh(tablesProvider(serviceType).future),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = waiterTableColumnCount(
                        constraints.maxWidth,
                      );

                      return GridView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          childAspectRatio: columns <= 2 ? 1.75 : 1.55,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                        ),
                        itemCount: filteredTables.length,
                        itemBuilder: (context, index) {
                          final table = filteredTables[index];
                          return _TableCard(
                            table: table,
                            onTap: () async {
                              if ((table.sessionStatus ?? '').toLowerCase() ==
                                  'billing') {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Bill already requested. This order is locked.',
                                    ),
                                  ),
                                );
                                return;
                              }

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
                      );
                    },
                  ),
                );
              },
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
      margin: EdgeInsets.zero,
      color: cardColor,
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      table.customerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(Icons.chevron_right, size: 18, color: statusColor),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(statusIcon, size: 16, color: statusColor),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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
