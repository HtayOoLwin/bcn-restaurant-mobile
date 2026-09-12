import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/search/order_search.dart';
import '../../../core/widgets/operational_refresh_indicator.dart';
import '../../../core/widgets/order_search_field.dart';
import '../../waiter/presentation/waiter_tables_screen.dart';
import '../domain/waiter_operation_models.dart';
import 'waiter_ready_screen.dart';

class WaiterProgressScreen extends ConsumerStatefulWidget {
  const WaiterProgressScreen({super.key});

  @override
  ConsumerState<WaiterProgressScreen> createState() =>
      _WaiterProgressScreenState();
}

class _WaiterProgressScreenState extends ConsumerState<WaiterProgressScreen> {
  String _searchQuery = '';
  String? _busyRow;
  String? _busyOrder;
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();

    _autoRefreshTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) {
        if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
        if (_busyRow != null || _busyOrder != null) return;

        final current = ref.read(waiterProgressProvider);
        if (current.isLoading) return;

        ref.invalidate(waiterProgressProvider);
      },
    );
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = ref.watch(waiterProgressProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Order Progress'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(waiterProgressProvider),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          OperationalRefreshIndicator(
            onRefresh: () => ref.invalidate(waiterProgressProvider),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: OrderSearchField(
              query: _searchQuery,
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),
          Expanded(
            child: progress.when(
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
                  onRefresh: () => ref.refresh(waiterProgressProvider.future),
                  child: data.orders.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 180),
                            Center(child: Text('No active orders')),
                          ],
                        )
                      : filteredOrders.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 180),
                            Center(
                              child: Text(
                                'No active orders match your search.',
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: filteredOrders.length,
                          itemBuilder: (context, index) => _ProgressCard(
                            order: filteredOrders[index],
                            busyRow: _busyRow,
                            busyOrder: _busyOrder,
                            onCancel: _cancelItem,
                            onRequestBill: _requestBill,
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

  Future<void> _requestBill(WaiterProgressOrder order) async {
    if (_busyOrder != null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Bill Request'),
        content: const Text(
          'Once you request the bill, this order will be locked. '
          'You cannot add or edit items after this. '
          'The bill will be printed automatically.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.print),
            label: const Text('Confirm & Print'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _busyOrder = order.name);
    try {
      final result = await ref
          .read(waiterOperationsRepositoryProvider)
          .requestBill(order.name);

      ref.invalidate(waiterProgressProvider);
      ref.invalidate(waiterReadyProvider);
      ref.invalidate(tablesProvider('dine_in'));
      ref.invalidate(tablesProvider('takeaway'));

      if (mounted) {
        final invoice = result['sales_invoice']?.toString() ?? '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              invoice.isEmpty
                  ? 'Bill requested. Order is now locked.'
                  : 'Bill requested. Draft Invoice: $invoice · Printing queued.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _busyOrder = null);
    }
  }

  Future<void> _cancelItem(WaiterProgressItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel item?'),
        content: Text(
          'Cancel ${item.itemName}? Only New items can be cancelled.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel Item'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busyRow = item.rowName);
    try {
      await ref
          .read(waiterOperationsRepositoryProvider)
          .itemAction(rowName: item.rowName, action: 'Cancel');
      ref.invalidate(waiterProgressProvider);
      ref.invalidate(waiterReadyProvider);
      ref.invalidate(tablesProvider('dine_in'));
      ref.invalidate(tablesProvider('takeaway'));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _busyRow = null);
    }
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({
    required this.order,
    required this.busyRow,
    required this.busyOrder,
    required this.onCancel,
    required this.onRequestBill,
  });

  final WaiterProgressOrder order;
  final String? busyRow;
  final String? busyOrder;
  final Future<void> Function(WaiterProgressItem item) onCancel;
  final Future<void> Function(WaiterProgressOrder order) onRequestBill;

  @override
  Widget build(BuildContext context) {
    final requesting = busyOrder == order.name;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.customer,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        order.name,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: requesting ? null : () => onRequestBill(order),
                  icon: requesting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.receipt_long),
                  label: Text(
                    requesting ? 'Requesting…' : 'Request for Bill',
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            ...order.items.map(
              (item) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(item.itemName),
                subtitle: Text(
                  '${item.qty.g} ${item.uom}${item.kitchenCounter?.isNotEmpty == true ? ' · ${item.kitchenCounter}' : ''}${item.kitchenNote?.isNotEmpty == true ? '\n${item.kitchenNote}' : ''}',
                ),
                trailing: item.canCancel
                    ? TextButton(
                        onPressed: requesting || busyRow == item.rowName
                            ? null
                            : () => onCancel(item),
                        child: const Text('Cancel'),
                      )
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

extension on double {
  String get g => this == roundToDouble() ? toInt().toString() : toString();
}
