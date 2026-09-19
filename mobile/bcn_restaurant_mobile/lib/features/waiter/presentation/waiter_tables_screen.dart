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
  (ref, customerGroup) =>
      ref.watch(tablesRepositoryProvider).getTables(customerGroup),
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
  String customerGroup = '';
  String _searchQuery = '';
  final _searchController = TextEditingController();
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();

    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;

      final current = ref.read(tablesProvider(customerGroup));
      if (current.isLoading) return;

      ref.invalidate(tablesProvider(customerGroup));
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
    final tables = ref.watch(tablesProvider(customerGroup));
    final response = tables.asData?.value;
    final customerGroups = response?.customerGroups ?? const <String>[];
    final effectiveCustomerGroup = customerGroup.isNotEmpty
        ? customerGroup
        : (response?.customerGroup ?? '');
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        titleSpacing: 16,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'BCN Restaurant',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
            ),
            const SizedBox(height: 2),
            Text(
              bootstrap?.fullName.isNotEmpty == true
                  ? '${bootstrap!.fullName} • Waiter'
                  : 'Waiter',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.82),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          if (bootstrap?.permissions.cashier == true)
            IconButton(
              tooltip: 'Cashier',
              onPressed: () => context.go('/cashier'),
              icon: const Icon(Icons.point_of_sale_outlined),
            ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(tablesProvider(customerGroup)),
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Column(
        children: [
          if (customerGroups.isNotEmpty)
            Container(
              width: double.infinity,
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final group in customerGroups) ...[
                      ChoiceChip(
                        selected: effectiveCustomerGroup == group,
                        label: Text(group),
                        showCheckmark: false,
                        selectedColor: colorScheme.primary,
                        backgroundColor: const Color(0xFFEAF1F8),
                        side: BorderSide.none,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        labelStyle: TextStyle(
                          color: effectiveCustomerGroup == group
                              ? Colors.white
                              : const Color(0xFF173A5E),
                          fontWeight: FontWeight.w700,
                        ),
                        onSelected: (_) {
                          if (effectiveCustomerGroup == group) return;
                          setState(() => customerGroup = group);
                        },
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
            ),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search table, customer, or order...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchQuery.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      ),
                isDense: true,
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),
          OperationalRefreshIndicator(
            onRefresh: () => ref.invalidate(tablesProvider(customerGroup)),
          ),
          Expanded(
            child: tables.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(error.toString(), textAlign: TextAlign.center),
                ),
              ),
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

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                      child: Row(
                        children: [
                          Icon(
                            Icons.table_restaurant_outlined,
                            size: 20,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Tables',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const Spacer(),
                          Text(
                            '${filteredTables.length} ${filteredTables.length == 1 ? 'Table' : 'Tables'}',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: const Color(0xFF66829D)),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: () =>
                            ref.refresh(tablesProvider(customerGroup).future),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final columns = waiterTableColumnCount(
                              constraints.maxWidth,
                            );

                            return GridView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: columns,
                                    childAspectRatio: columns == 3
                                        ? 0.88
                                        : columns <= 2
                                        ? 1.15
                                        : 1.02,
                                    crossAxisSpacing: 10,
                                    mainAxisSpacing: 10,
                                  ),
                              itemCount: filteredTables.length,
                              itemBuilder: (context, index) {
                                final table = filteredTables[index];
                                return _TableCard(
                                  table: table,
                                  onTap: () async {
                                    if ((table.sessionStatus ?? '')
                                            .toLowerCase() ==
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

                                    ref.invalidate(
                                      tablesProvider(customerGroup),
                                    );
                                  },
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        height: 66,
        selectedIndex: 0,
        backgroundColor: Colors.white,
        indicatorColor: colorScheme.primary.withValues(alpha: 0.12),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (index) {
          if (index == 1) {
            context.push('/waiter-progress');
          } else if (index == 2) {
            context.push('/settings');
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Tables',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long_rounded),
            label: 'Orders',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'Settings',
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

    Color cardBackground;
    Color borderColor;
    Color statusColor;
    Color statusBackground;
    IconData statusIcon;

    switch (status.toLowerCase()) {
      case 'occupied':
        cardBackground = const Color(0xFFFFEFF1);
        borderColor = const Color(0xFFF1CDD2);
        statusColor = const Color(0xFFB94A55);
        statusBackground = const Color(0xFFFFE1E5);
        statusIcon = Icons.person_outline_rounded;
        break;
      case 'billing':
        cardBackground = const Color(0xFFEAF2FA);
        borderColor = const Color(0xFFC9DCEF);
        statusColor = const Color(0xFF2E67A0);
        statusBackground = const Color(0xFFDCEAF7);
        statusIcon = Icons.point_of_sale_outlined;
        break;
      case 'available':
      default:
        cardBackground = const Color(0xFFE8F6EF);
        borderColor = const Color(0xFFCBE8DA);
        statusColor = const Color(0xFF2E7D5B);
        statusBackground = const Color(0xFFD9F0E4);
        statusIcon = Icons.check_circle_outline_rounded;
        break;
    }

    return Material(
      color: cardBackground,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.table_restaurant_outlined,
                size: 30,
                color: const Color(0xFF315F8E),
              ),
              const SizedBox(height: 6),
              Text(
                table.customerName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: const Color(0xFF102F4F),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusBackground,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, size: 13, color: statusColor),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: statusColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
