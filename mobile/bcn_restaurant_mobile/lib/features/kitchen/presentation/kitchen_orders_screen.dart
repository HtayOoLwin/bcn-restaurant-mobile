import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/presentation/auth_controller.dart';
import '../../../core/search/order_search.dart';
import '../../../core/widgets/operational_refresh_indicator.dart';
import '../../../core/widgets/order_search_field.dart';
import '../../waiter/presentation/waiter_tables_screen.dart';
import '../data/kitchen_printer_service.dart';
import '../data/kitchen_repository.dart';
import '../domain/kitchen_models.dart';
import 'kitchen_notification_badge.dart';

final kitchenRepositoryProvider = Provider<KitchenRepository>(
  (ref) => KitchenRepository(ref.watch(apiClientProvider)),
);

final printerServiceProvider = Provider<KitchenPrinterService>(
  (ref) => const KitchenPrinterService(),
);

final kitchenOrdersProvider = FutureProvider.family<KitchenOrdersResponse, String>(
  (ref, status) => ref.watch(kitchenRepositoryProvider).getOrders(status: status),
);

class KitchenOrdersScreen extends ConsumerStatefulWidget {
  const KitchenOrdersScreen({super.key});

  @override
  ConsumerState<KitchenOrdersScreen> createState() => _KitchenOrdersScreenState();
}

class _KitchenOrdersScreenState extends ConsumerState<KitchenOrdersScreen> {
  String _status = 'All';
  String _searchQuery = '';
  String? _busyRow;
  String? _busyPrintKey;

  @override
  Widget build(BuildContext context) {
    final bootstrap = ref.watch(authControllerProvider).asData?.value.bootstrap;
    final response = ref.watch(kitchenOrdersProvider(_status));
    final kitchenNewOrderCount = ref.watch(kitchenNewOrderCountProvider).asData?.value ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(bootstrap?.fullName.isNotEmpty == true ? bootstrap!.fullName : 'Kitchen'),
        actions: [
          if (bootstrap?.permissions.waiter == true)
            IconButton(
              tooltip: 'Waiter',
              onPressed: () => context.go('/tables'),
              icon: const Icon(Icons.table_restaurant),
            ),
          if (bootstrap?.permissions.cashier == true)
            IconButton(
              tooltip: 'Cashier',
              onPressed: () => context.go('/cashier'),
              icon: const Icon(Icons.point_of_sale),
            ),
          IconButton(
            tooltip: 'New Kitchen Orders',
            onPressed: () => setState(() => _status = 'New'),
            icon: kitchenNewOrderCount > 0
                ? Badge.count(
                    count: kitchenNewOrderCount,
                    child: const Icon(Icons.notifications),
                  )
                : const Icon(Icons.notifications),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: () {
              ref.invalidate(kitchenOrdersProvider(_status));
              ref.invalidate(kitchenNewOrderCountProvider);
            },
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
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'All', label: Text('All')),
                  ButtonSegment(value: 'New', label: Text('New')),
                  ButtonSegment(value: 'Preparing', label: Text('Preparing')),
                  ButtonSegment(value: 'Ready', label: Text('Ready')),
                ],
                selected: {_status},
                onSelectionChanged: (value) => setState(() => _status = value.first),
              ),
            ),
          ),
          OperationalRefreshIndicator(
            onRefresh: () {
              ref.invalidate(kitchenOrdersProvider(_status));
              ref.invalidate(kitchenNewOrderCountProvider);
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: OrderSearchField(
              query: _searchQuery,
              labelText: 'Search table, order or item',
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),
          Expanded(
            child: response.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(error.toString(), textAlign: TextAlign.center),
                ),
              ),
              data: (data) {
                final filteredOrders = data.orders
                    .where(
                      (order) => matchesOrderSearch(
                        queryText: _searchQuery,
                        tableName: order.customer,
                        orderNumbers: [order.name],
                        searchTerms: order.items.expand(
                          (item) => [item.itemName, item.itemCode],
                        ),
                      ),
                    )
                    .toList();
                return RefreshIndicator(
                  onRefresh: () => ref.refresh(kitchenOrdersProvider(_status).future),
                  child: data.orders.isEmpty
                      ? ListView(children: const [
                          SizedBox(height: 160),
                          Center(child: Text('No active kitchen items')),
                        ])
                      : filteredOrders.isEmpty
                          ? ListView(children: const [
                              SizedBox(height: 160),
                              Center(child: Text('No kitchen orders match your search.')),
                            ])
                          : ListView.builder(
                              padding: const EdgeInsets.all(12),
                              itemCount: filteredOrders.length,
                              itemBuilder: (context, index) => _OrderCard(
                                order: filteredOrders[index],
                                response: data,
                                busyRow: _busyRow,
                                busyPrintKey: _busyPrintKey,
                                onAction: _runAction,
                                onPrint: _printOrderCounter,
                              ),
                            ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _printOrderCounter(
    KitchenOrder order,
    String counterName,
    KitchenPrinterSettings? settings,
    List<KitchenOrderItem> items,
  ) async {
    if (settings == null || !settings.isConfigured) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Printer is not configured for $counterName.')),
        );
      }
      return;
    }

    final printKey = '${order.name}|$counterName';
    final isReprint = items.any((item) => item.printCount > 0);
    setState(() => _busyPrintKey = printKey);
    var physicalPrintSucceeded = false;
    try {
      await ref.read(printerServiceProvider).printOrder(
            order: order,
            counterName: counterName,
            settings: settings,
            items: items,
            isReprint: isReprint,
          );
      physicalPrintSucceeded = true;
      await ref.read(kitchenRepositoryProvider).recordPrint(
            orderName: order.name,
            counterName: counterName,
            rowNames: items.map((item) => item.rowName).toList(),
          );
      ref.invalidate(kitchenOrdersProvider(_status));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${isReprint ? 'Reprinted' : 'Printed'} · ${order.customer} · $counterName')),
        );
      }
    } catch (error) {
      if (mounted) {
        final prefix = physicalPrintSucceeded
            ? 'Print was sent, but print history could not be recorded. '
            : '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$prefix$error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busyPrintKey = null);
    }
  }

  Future<void> _runAction(KitchenOrderItem item, String action) async {
    setState(() => _busyRow = item.rowName);
    try {
      await ref.read(kitchenRepositoryProvider).updateItemStatus(rowName: item.rowName, action: action);
      ref.invalidate(kitchenOrdersProvider(_status));
      ref.invalidate(kitchenNewOrderCountProvider);
      ref.invalidate(tablesProvider('dine_in'));
      ref.invalidate(tablesProvider('takeaway'));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$action · ${item.itemName}')));
      }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _busyRow = null);
    }
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.response,
    required this.busyRow,
    required this.busyPrintKey,
    required this.onAction,
    required this.onPrint,
  });

  final KitchenOrder order;
  final KitchenOrdersResponse response;
  final String? busyRow;
  final String? busyPrintKey;
  final Future<void> Function(KitchenOrderItem item, String action) onAction;
  final Future<void> Function(
    KitchenOrder order,
    String counterName,
    KitchenPrinterSettings? settings,
    List<KitchenOrderItem> items,
  ) onPrint;

  @override
  Widget build(BuildContext context) {
    final itemsByCounter = <String, List<KitchenOrderItem>>{};
    for (final item in order.items) {
      itemsByCounter.putIfAbsent(item.kitchenCounter, () => []).add(item);
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(order.customer, style: Theme.of(context).textTheme.titleLarge)),
                Text(order.preparationSummary),
              ],
            ),
            const SizedBox(height: 4),
            Text(order.name, style: Theme.of(context).textTheme.bodySmall),
            const Divider(height: 24),
            ...itemsByCounter.entries.expand((entry) {
              final counterName = entry.key;
              final counterItems = entry.value;
              final printKey = '${order.name}|$counterName';
              final printing = busyPrintKey == printKey;
              final isReprint = counterItems.any((item) => item.printCount > 0);
              final lastPrintedAt = _latestPrintedAt(counterItems);

              return [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        counterName,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: printing
                          ? null
                          : () => onPrint(
                                order,
                                counterName,
                                response.settingsForCounter(counterName),
                                counterItems,
                              ),
                      icon: printing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.print),
                      label: Text(isReprint ? 'Reprint' : 'Print'),
                    ),
                  ],
                ),
                if (lastPrintedAt != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Printed ${_formatPrintedTime(lastPrintedAt)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 8),
                ...counterItems.map(
                  (item) => _KitchenLine(
                    item: item,
                    busy: busyRow == item.rowName,
                    onAction: onAction,
                  ),
                ),
              ];
            }),
          ],
        ),
      ),
    );
  }

  static DateTime? _latestPrintedAt(List<KitchenOrderItem> items) {
    DateTime? latest;
    for (final item in items) {
      final value = item.lastPrintedAt;
      if (value != null && (latest == null || value.isAfter(latest))) latest = value;
    }
    return latest;
  }

  static String _formatPrintedTime(DateTime value) {
    final local = value.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

class _KitchenLine extends StatelessWidget {
  const _KitchenLine({required this.item, required this.busy, required this.onAction});

  final KitchenOrderItem item;
  final bool busy;
  final Future<void> Function(KitchenOrderItem item, String action) onAction;

  @override
  Widget build(BuildContext context) {
    final action = item.nextAction;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.itemName, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('${item.qty.g} ${item.uom} · ${item.kitchenCounter} · ${item.displayPreparationStatus}'),
          if (item.kitchenNote?.isNotEmpty == true) ...[
            const SizedBox(height: 6),
            Text('Note: ${item.kitchenNote}', style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
          if (action != null) ...[
            const SizedBox(height: 8),
            FilledButton(
              onPressed: busy ? null : () => onAction(item, action),
              child: busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(action),
            ),
          ],
        ],
      ),
    );
  }
}

extension on double {
  String get g => this == roundToDouble() ? toInt().toString() : toString();
}
