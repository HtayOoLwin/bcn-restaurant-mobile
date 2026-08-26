import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_controller.dart';
import '../data/kitchen_repository.dart';
import '../domain/kitchen_models.dart';

final kitchenRepositoryProvider = Provider<KitchenRepository>(
  (ref) => KitchenRepository(ref.watch(apiClientProvider)),
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
  String? _busyRow;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) ref.invalidate(kitchenOrdersProvider(_status));
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bootstrap = ref.watch(authControllerProvider).asData?.value.bootstrap;
    final response = ref.watch(kitchenOrdersProvider(_status));

    return Scaffold(
      appBar: AppBar(
        title: Text(bootstrap?.fullName.isNotEmpty == true ? bootstrap!.fullName : 'Kitchen'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(kitchenOrdersProvider(_status)),
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
                  ButtonSegment(value: 'Accepted', label: Text('Accepted')),
                  ButtonSegment(value: 'Preparing', label: Text('Preparing')),
                  ButtonSegment(value: 'Ready', label: Text('Ready')),
                ],
                selected: {_status},
                onSelectionChanged: (value) => setState(() => _status = value.first),
              ),
            ),
          ),
          Expanded(
            child: response.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(error.toString(), textAlign: TextAlign.center),
              )),
              data: (data) => RefreshIndicator(
                onRefresh: () => ref.refresh(kitchenOrdersProvider(_status).future),
                child: data.orders.isEmpty
                    ? ListView(children: const [
                        SizedBox(height: 160),
                        Center(child: Text('No active kitchen items')),
                      ])
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: data.orders.length,
                        itemBuilder: (context, index) => _OrderCard(
                          order: data.orders[index],
                          busyRow: _busyRow,
                          onAction: _runAction,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _runAction(KitchenOrderItem item, String action) async {
    setState(() => _busyRow = item.rowName);
    try {
      await ref.read(kitchenRepositoryProvider).updateItemStatus(rowName: item.rowName, action: action);
      ref.invalidate(kitchenOrdersProvider(_status));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$action · ${item.itemName}')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _busyRow = null);
    }
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, required this.busyRow, required this.onAction});

  final KitchenOrder order;
  final String? busyRow;
  final Future<void> Function(KitchenOrderItem item, String action) onAction;

  @override
  Widget build(BuildContext context) {
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
            ...order.items.map((item) => _KitchenLine(
                  item: item,
                  busy: busyRow == item.rowName,
                  onAction: onAction,
                )),
          ],
        ),
      ),
    );
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
          Text('${item.qty.g} ${item.uom} · ${item.kitchenCounter} · ${item.preparationStatus}'),
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
