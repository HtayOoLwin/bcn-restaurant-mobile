import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_controller.dart';
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
  Timer? _timer;
  String? _busyKey;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) ref.invalidate(waiterReadyProvider);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = ref.watch(waiterReadyProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ready to Serve'),
        actions: [
          IconButton(onPressed: () => ref.invalidate(waiterReadyProvider), icon: const Icon(Icons.refresh)),
        ],
      ),
      body: ready.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text(error.toString())),
        data: (data) => RefreshIndicator(
          onRefresh: () => ref.refresh(waiterReadyProvider.future),
          child: data.orders.isEmpty
              ? ListView(children: const [SizedBox(height: 180), Center(child: Text('Nothing is ready yet'))])
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: data.orders.length,
                  itemBuilder: (context, index) {
                    final order = data.orders[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(order.customer, style: Theme.of(context).textTheme.titleLarge),
                            Text(order.name, style: Theme.of(context).textTheme.bodySmall),
                            const Divider(height: 24),
                            ...order.items.map((item) => ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(item.itemName),
                                  subtitle: Text('${item.qty.g} ${item.uom} · ${item.kitchenCounter ?? 'Kitchen'}${item.kitchenNote?.isNotEmpty == true ? '\n${item.kitchenNote}' : ''}'),
                                  trailing: FilledButton(
                                    onPressed: _busyKey == item.rowName ? null : () => _itemAction(item),
                                    child: _busyKey == item.rowName
                                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                        : const Text('Served'),
                                  ),
                                )),
                            if (order.canServeWhole) ...[
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.tonal(
                                  onPressed: _busyKey == order.name ? null : () => _serveWhole(order),
                                  child: const Text('Serve Whole Order'),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }

  Future<void> _itemAction(WaiterReadyItem item) async {
    setState(() => _busyKey = item.rowName);
    try {
      await ref.read(waiterOperationsRepositoryProvider).itemAction(rowName: item.rowName, action: 'Mark Served');
      ref.invalidate(waiterReadyProvider);
      ref.invalidate(waiterProgressProvider);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _busyKey = null);
    }
  }

  Future<void> _serveWhole(WaiterReadyOrder order) async {
    setState(() => _busyKey = order.name);
    try {
      await ref.read(waiterOperationsRepositoryProvider).serveWholeOrder(order.name);
      ref.invalidate(waiterReadyProvider);
      ref.invalidate(waiterProgressProvider);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _busyKey = null);
    }
  }
}

extension on double {
  String get g => this == roundToDouble() ? toInt().toString() : toString();
}
