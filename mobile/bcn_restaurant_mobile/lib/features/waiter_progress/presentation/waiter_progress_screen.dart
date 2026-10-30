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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.invalidate(waiterProgressProvider);
    });

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
                            onPay: _pay,
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
        content: const Text('Do you want to print bill?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.print),
            label: const Text('Yes'),
          ),
        ],
      ),
    );

    if (confirmed == null) return;

    setState(() => _busyOrder = order.name);
    try {
      final result = await ref
          .read(waiterOperationsRepositoryProvider)
          .requestBill(order.name, printBill: confirmed);

      ref.invalidate(waiterProgressProvider);
      ref.invalidate(waiterReadyProvider);
      ref.invalidate(tablesProvider('dine_in'));
      ref.invalidate(tablesProvider('takeaway'));

      if (mounted) {
        final printJob = result['print_job']?.toString() ?? '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              printJob.isEmpty
                  ? 'Bill requested successfully.'
                  : 'Bill requested · Print queued: $printJob',
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

  Future<void> _pay(WaiterProgressOrder order) async {
    if (_busyOrder != null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: Text('Send ${order.customer} to cashier for payment?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Pay'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busyOrder = order.name);
    try {
      await ref.read(waiterOperationsRepositoryProvider).markReadyForPayment(order.name);
      ref.invalidate(waiterProgressProvider);
      ref.invalidate(tablesProvider('dine_in'));
      ref.invalidate(tablesProvider('takeaway'));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sent to cashier for payment.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
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

class _ProgressCard extends StatefulWidget {
  const _ProgressCard({
    required this.order,
    required this.busyRow,
    required this.busyOrder,
    required this.onCancel,
    required this.onRequestBill,
    required this.onPay,
  });

  final WaiterProgressOrder order;
  final String? busyRow;
  final String? busyOrder;
  final Future<void> Function(WaiterProgressItem item) onCancel;
  final Future<void> Function(WaiterProgressOrder order) onRequestBill;
  final Future<void> Function(WaiterProgressOrder order) onPay;

  @override
  State<_ProgressCard> createState() => _ProgressCardState();
}

class _ProgressCardState extends State<_ProgressCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final requesting = widget.busyOrder == widget.order.name;
    const payGreen = Color(0xFF159B55);
    const billBlue = Color(0xFF1F5F92);

    final orderDetails = InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => setState(() => _expanded = !_expanded),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    widget.order.customer,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(_expanded ? Icons.expand_less : Icons.expand_more),
              ],
            ),
            const SizedBox(height: 6),
            Tooltip(
              message: widget.order.name,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFE3EFFC),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  widget.order.name,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF153D69),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    final payButton = widget.order.billRevision > 0
        ? FilledButton.icon(
            onPressed: requesting ? null : () => widget.onPay(widget.order),
            style: FilledButton.styleFrom(
              backgroundColor: payGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
            icon: const Icon(Icons.payments_outlined, size: 18),
            label: const Text('Pay', maxLines: 1),
          )
        : null;

    final billButton = FilledButton.icon(
      onPressed: requesting ? null : () => widget.onRequestBill(widget.order),
      style: FilledButton.styleFrom(
        backgroundColor: billBlue,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      icon: requesting
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.receipt_long, size: 18),
      label: Text(
        requesting ? 'Requesting…' : 'Request for Bill',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 570;
            final actions = Row(
              children: [
                if (payButton != null) ...[
                  Expanded(flex: 2, child: payButton),
                  const SizedBox(width: 8),
                ],
                Expanded(flex: 3, child: billButton),
              ],
            );

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (compact) ...[
                  orderDetails,
                  const SizedBox(height: 10),
                  actions,
                ] else
                  Row(
                    children: [
                      Expanded(child: orderDetails),
                      const SizedBox(width: 16),
                      SizedBox(width: payButton == null ? 190 : 320, child: actions),
                    ],
                  ),
                if (_expanded) ...[
                  const Divider(height: 24),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECF3FA),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Items (${widget.order.items.length})',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF153D69),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...widget.order.items.map(
                    (item) => Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 5,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            constraints: const BoxConstraints(minWidth: 42),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE3EFFC),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${item.qty.g} ×',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFF153D69),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                Text(item.itemName),
                                if (item.foc)
                                  const _ProgressItemBadge(
                                    label: 'FOC',
                                    color: Color(0xFFC62828),
                                    background: Color(0xFFFFEBEE),
                                  ),
                                if (item.parcel)
                                  const _ProgressItemBadge(
                                    label: 'PARCEL',
                                    color: Color(0xFF18834B),
                                    background: Color(0xFFE3F6E9),
                                  ),
                              ],
                            ),
                          ),
                          if (item.canCancel) ...[
                            const SizedBox(width: 6),
                            TextButton(
                              onPressed: requesting ||
                                      widget.busyRow == item.rowName
                                  ? null
                                  : () => widget.onCancel(item),
                              child: const Text('Cancel'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ProgressItemBadge extends StatelessWidget {
  const _ProgressItemBadge({
    required this.label,
    required this.color,
    required this.background,
  });

  final String label;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

extension on double {
  String get g => this == roundToDouble() ? toInt().toString() : toString();
}
