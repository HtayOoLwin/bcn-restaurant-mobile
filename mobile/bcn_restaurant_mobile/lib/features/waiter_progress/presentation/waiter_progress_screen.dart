import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/waiter_operation_models.dart';
import 'waiter_ready_screen.dart';

class WaiterProgressScreen extends ConsumerStatefulWidget {
  const WaiterProgressScreen({super.key});

  @override
  ConsumerState<WaiterProgressScreen> createState() => _WaiterProgressScreenState();
}

class _WaiterProgressScreenState extends ConsumerState<WaiterProgressScreen> {
  Timer? _timer;
  String? _busyRow;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) ref.invalidate(waiterProgressProvider);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = ref.watch(waiterProgressProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Order Progress'),
        actions: [IconButton(onPressed: () => ref.invalidate(waiterProgressProvider), icon: const Icon(Icons.refresh))],
      ),
      body: progress.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text(error.toString())),
        data: (data) => RefreshIndicator(
          onRefresh: () => ref.refresh(waiterProgressProvider.future),
          child: data.orders.isEmpty
              ? ListView(children: const [SizedBox(height: 180), Center(child: Text('No active orders'))])
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: data.orders.length,
                  itemBuilder: (context, index) => _ProgressCard(
                    order: data.orders[index],
                    busyRow: _busyRow,
                    onCancel: _cancelItem,
                  ),
                ),
        ),
      ),
    );
  }

  Future<void> _cancelItem(WaiterProgressItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel item?'),
        content: Text('Cancel ${item.itemName}? Only New items can be cancelled.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cancel Item')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busyRow = item.rowName);
    try {
      await ref.read(waiterOperationsRepositoryProvider).itemAction(rowName: item.rowName, action: 'Cancel');
      ref.invalidate(waiterProgressProvider);
      ref.invalidate(waiterReadyProvider);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _busyRow = null);
    }
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.order, required this.busyRow, required this.onCancel});

  final WaiterProgressOrder order;
  final String? busyRow;
  final Future<void> Function(WaiterProgressItem item) onCancel;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: Text(order.customer, style: Theme.of(context).textTheme.titleLarge)),
              Text(order.preparationSummary),
            ]),
            Text(order.name, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                Chip(label: Text('New ${order.newQty.g}')),
                Chip(label: Text('Preparing ${order.preparingQty.g}')),
                Chip(label: Text('Ready ${order.readyQty.g}')),
                Chip(label: Text('Served ${order.servedQty.g}')),
              ],
            ),
            const Divider(height: 24),
            ...order.items.map((item) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(item.itemName),
                  subtitle: Text('${item.qty.g} ${item.uom} · ${item.status}${item.kitchenCounter?.isNotEmpty == true ? ' · ${item.kitchenCounter}' : ''}${item.kitchenNote?.isNotEmpty == true ? '\n${item.kitchenNote}' : ''}'),
                  trailing: item.canCancel
                      ? TextButton(
                          onPressed: busyRow == item.rowName ? null : () => onCancel(item),
                          child: const Text('Cancel'),
                        )
                      : null,
                )),
          ],
        ),
      ),
    );
  }
}

extension on double {
  String get g => this == roundToDouble() ? toInt().toString() : toString();
}
