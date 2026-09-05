import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/search/order_search.dart';
import '../../../core/widgets/operational_refresh_indicator.dart';
import '../../../core/widgets/order_search_field.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../waiter/presentation/waiter_tables_screen.dart';
import '../data/waiter_operations_repository.dart';
import '../domain/waiter_operation_models.dart';

final waiterOperationsRepositoryProvider = Provider<WaiterOperationsRepository>(
  (ref) => WaiterOperationsRepository(ref.watch(apiClientProvider)),
);

final waiterReadyProvider = FutureProvider<WaiterReadyResponse>(
  (ref) => ref.watch(waiterOperationsRepositoryProvider).getReadyOrders(),
);

final waiterProgressProvider = FutureProvider<WaiterProgressResponse>(
  (ref) => ref.watch(waiterOperationsRepositoryProvider).getProgress(),
);

class WaiterReadyScreen extends ConsumerStatefulWidget {
  const WaiterReadyScreen({super.key});

  @override
  ConsumerState<WaiterReadyScreen> createState() => _WaiterReadyScreenState();
}

class _WaiterReadyScreenState extends ConsumerState<WaiterReadyScreen> {
  String _searchQuery = '';
  String? _busyKey;

  @override
  Widget build(BuildContext context) {
    final ready = ref.watch(waiterReadyProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ready to Serve'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(waiterReadyProvider),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          OperationalRefreshIndicator(
            onRefresh: () => ref.invalidate(waiterReadyProvider),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: OrderSearchField(
              query: _searchQuery,
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),
          Expanded(
            child: ready.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text(error.toString())),
              data: (data) {
                final filteredOrders = data.orders
                    .where(
                      (order) => matchesOrderSearch(
                        queryText: _searchQuery,
                        tableName: order.customer,
                        orderNumbers: [order.name],
                      ),
                    )
                    .toList();
                return RefreshIndicator(
                  onRefresh: () => ref.refresh(waiterReadyProvider.future),
                  child: data.orders.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 180),
                            Center(child: Text('Nothing is ready yet')),
                          ],
                        )
                      : filteredOrders.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 180),
                            Center(
                              child: Text('No ready orders match your search.'),
                            ),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: filteredOrders.length,
                          itemBuilder: (context, index) {
                            final order = filteredOrders[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      order.customer,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleLarge,
                                    ),
                                    Text(
                                      order.name,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                    const Divider(height: 24),
                                    ...order.items.map(
                                      (item) => ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        title: Text(item.itemName),
                                        subtitle: Text(
                                          '${item.qty.g} ${item.uom} · ${item.kitchenCounter ?? 'Kitchen'}${item.kitchenNote?.isNotEmpty == true ? '\n${item.kitchenNote}' : ''}',
                                        ),
                                        trailing: FilledButton(
                                          onPressed: _busyKey == item.rowName
                                              ? null
                                              : () => _itemAction(item),
                                          child: _busyKey == item.rowName
                                              ? const SizedBox(
                                                  width: 18,
                                                  height: 18,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                      ),
                                                )
                                              : const Text('Served'),
                                        ),
                                      ),
                                    ),
                                    if (order.canServeWhole) ...[
                                      const SizedBox(height: 8),
                                      SizedBox(
                                        width: double.infinity,
                                        child: FilledButton.tonal(
                                          onPressed: _busyKey == order.name
                                              ? null
                                              : () => _serveWhole(order),
                                          child: const Text(
                                            'Serve Whole Order',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
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

  Future<void> _itemAction(WaiterReadyItem item) async {
    setState(() => _busyKey = item.rowName);
    try {
      await ref
          .read(waiterOperationsRepositoryProvider)
          .itemAction(rowName: item.rowName, action: 'Mark Served');
      ref.invalidate(waiterReadyProvider);
      ref.invalidate(waiterProgressProvider);
      ref.invalidate(tablesProvider('dine_in'));
      ref.invalidate(tablesProvider('takeaway'));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _busyKey = null);
    }
  }

  Future<void> _serveWhole(WaiterReadyOrder order) async {
    setState(() => _busyKey = order.name);
    try {
      await ref
          .read(waiterOperationsRepositoryProvider)
          .serveWholeOrder(order.name);
      ref.invalidate(waiterReadyProvider);
      ref.invalidate(waiterProgressProvider);
      ref.invalidate(tablesProvider('dine_in'));
      ref.invalidate(tablesProvider('takeaway'));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _busyKey = null);
    }
  }
}

extension on double {
  String get g => this == roundToDouble() ? toInt().toString() : toString();
}
