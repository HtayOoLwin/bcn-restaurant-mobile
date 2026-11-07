import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/search/order_search.dart';
import '../../../core/formatters/amount_format.dart';
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
        if (_busyRow != null) return;

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
                            onCancel: _cancelItem,
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

  Future<void> _cancelItem(WaiterProgressItem item) async {
    final maxCancelable = item.cancelableQty.floor();
    if (maxCancelable < 1) return;

    var selectedQty = 1;
    final cancelQty = await showDialog<int>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, updateDialog) => AlertDialog(
          title: const Text('Cancel Item Quantity'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.itemName,
                style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text('Ordered: ${item.qty.g} ${item.uom}'),
              Text('Available to cancel: $maxCancelable ${item.uom}'),
              const SizedBox(height: 16),
              const Text('Cancel Quantity',
                style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton.filledTonal(
                    tooltip: 'Decrease cancel quantity',
                    onPressed: selectedQty > 1
                        ? () => updateDialog(() => selectedQty--)
                        : null,
                    icon: const Icon(Icons.remove),
                  ),
                  SizedBox(
                    width: 70,
                    child: Text(
                      '$selectedQty',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Increase cancel quantity',
                    onPressed: selectedQty < maxCancelable
                        ? () => updateDialog(() => selectedQty++)
                        : null,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Remaining quantity: ${(item.qty - selectedQty).g} ${item.uom}',
                style: const TextStyle(color: Color(0xFF617B94)),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Keep'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, selectedQty),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFD32F2F),
                foregroundColor: Colors.white,
              ),
              child: const Text('Confirm Cancel'),
            ),
          ],
        ),
      ),
    );
    if (cancelQty == null || !mounted) return;

    final unprintedQty = (item.qty - item.printedQty).clamp(0.0, item.qty);
    final printedCancelQty = (cancelQty - unprintedQty).clamp(0.0, item.printedQty);
    if (printedCancelQty > 0) {
      final acknowledged = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Kitchen Already Printed'),
          content: Text(
            '${printedCancelQty.toStringAsFixed(0)} × ${item.itemName} '
            'has already been printed to the kitchen. '
            'Cancel this quantity anyway? '
            'Please notify the kitchen manually. '
            'No cancellation ticket will be printed.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Keep'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFD32F2F),
                foregroundColor: Colors.white,
              ),
              child: const Text('Confirm Cancel'),
            ),
          ],
        ),
      );
      if (acknowledged != true || !mounted) return;
    }

    setState(() => _busyRow = item.rowName);
    try {
      await ref
          .read(waiterOperationsRepositoryProvider)
          .itemAction(
            rowName: item.rowName,
            action: 'Cancel',
            cancelQty: cancelQty,
            confirmPrintedCancel: printedCancelQty > 0,
          );
      ref.invalidate(waiterProgressProvider);
      ref.invalidate(waiterReadyProvider);
      ref.invalidate(tablesProvider('dine_in'));
      ref.invalidate(tablesProvider('takeaway'));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(
            printedCancelQty > 0
                ? 'Cancelled $cancelQty × ${item.itemName}. Please notify the kitchen manually.'
                : 'Cancelled $cancelQty × ${item.itemName} successfully.',
          )),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
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
    required this.onCancel,
  });

  final WaiterProgressOrder order;
  final String? busyRow;
  final Future<void> Function(WaiterProgressItem item) onCancel;

  @override
  State<_ProgressCard> createState() => _ProgressCardState();
}

class _ProgressCardState extends State<_ProgressCard> {
  bool _expanded = false;
  bool _cancelMode = false;

  @override
  Widget build(BuildContext context) {

    final cardColors = <Color>[
      const Color(0xFFB9D5F8),
      const Color(0xFFB7E3C7),
      const Color(0xFFF5D1A5),
      const Color(0xFFD9C3F3),
    ];
    final cardIndex = widget.order.name.codeUnits.fold<int>(0, (sum, code) => sum + code) % cardColors.length;
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

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      color: cardColors[cardIndex],
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                orderDetails,
                if (_expanded) ...[
                  const Divider(height: 24),
                  if (widget.order.roomPreview != null) ...[
                    _RoomChargePreviewCard(
                      preview: widget.order.roomPreview!,
                      currency: widget.order.currency,
                    ),
                    const SizedBox(height: 12),
                  ],
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDDEBFA),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Items (${widget.order.items.length})',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF153D69),
                            ),
                          ),
                        ),
                        OutlinedButton.icon(
                            onPressed: widget.busyRow != null
                                ? null
                                : () {
                                    if (!_cancelMode &&
                                        !widget.order.items.any((item) => item.canCancel)) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'No items can be cancelled for this order.',
                                          ),
                                        ),
                                      );
                                      return;
                                    }
                                    setState(() => _cancelMode = !_cancelMode);
                                  },
                            icon: Icon(
                              _cancelMode
                                  ? Icons.check_rounded
                                  : Icons.delete_outline_rounded,
                              size: 16,
                            ),
                            label: Text(_cancelMode ? 'Done' : 'Cancel Items'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _cancelMode
                                  ? const Color(0xFF156B51)
                                  : const Color(0xFFD32F2F),
                              side: BorderSide(
                                color: _cancelMode
                                    ? const Color(0xFF156B51)
                                    : const Color(0xFFD32F2F),
                              ),
                              backgroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 5,
                              ),
                              minimumSize: const Size(0, 32),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              textStyle: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...widget.order.items.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(left: 4, right: 0, top: 5, bottom: 5),
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
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
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
                                const SizedBox(height: 4),
                                Text(
                                  '@ ${formatAmount(item.rate)}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF436783),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                formatMoney(item.amount, widget.order.currency),
                                textAlign: TextAlign.right,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              if (_cancelMode && item.canCancel) ...[
                                const SizedBox(height: 6),
                                OutlinedButton.icon(
                                  onPressed: widget.busyRow == item.rowName
                                      ? null
                                      : () => widget.onCancel(item),
                                  icon: const Icon(Icons.delete_outline_rounded, size: 17),
                                  label: const Text('Cancel'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFFD32F2F),
                                    side: const BorderSide(
                                      color: Color(0xFFD32F2F),
                                      width: 1.4,
                                    ),
                                    backgroundColor: const Color(0xFFFFF5F5),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 7,
                                    ),
                                    minimumSize: const Size(0, 36),
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    textStyle: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                const Divider(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Subtotal'),
                    Text(formatMoney(widget.order.netTotal, widget.order.currency)),
                  ],
                ),
                for (final rawTax in widget.order.taxes)
                  if (rawTax is Map && ((rawTax['amount'] as num?) ?? 0).abs() > 0.00001)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(rawTax['label']?.toString() ?? 'Tax'),
                          Text(formatMoney((rawTax['amount'] as num?) ?? 0, widget.order.currency)),
                        ],
                      ),
                    ),
                const Divider(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Grand Total', style: TextStyle(fontWeight: FontWeight.bold)),
                    Text(formatMoney(widget.order.grandTotal, widget.order.currency),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                  ],
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

class _RoomChargePreviewCard extends StatelessWidget {
  const _RoomChargePreviewCard({
    required this.preview,
    required this.currency,
  });

  final WaiterRoomPreview preview;
  final String currency;

  // Frappe dates are already in the restaurant's local time. Reformat
  // their text without treating a timezone-free value as UTC.
  String _formatDateTime(String value) {
    final match = RegExp(
      r'^(\\d{4})-(\\d{2})-(\\d{2})[ T](\\d{2}):(\\d{2}):(\\d{2})',
    ).firstMatch(value.trim());
    if (match == null) return value;
    return '${match.group(3)}/${match.group(2)}/${match.group(1)} '
        '${match.group(4)}:${match.group(5)}:${match.group(6)}';
  }

  @override
  Widget build(BuildContext context) {
    final seconds = preview.elapsedSeconds.round().clamp(0, 86400000);
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final remainingSeconds = seconds % 60;
    final elapsedText =
        '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${remainingSeconds.toString().padLeft(2, '0')}';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F8FF),
        border: Border.all(color: const Color(0xFFB5D3F0)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.meeting_room_outlined,
                  size: 19, color: Color(0xFF153D69)),
              const SizedBox(width: 7),
              const Expanded(
                child: Text('Room Charges',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
              Text(preview.isLive ? 'LIVE PREVIEW' : 'FINAL',
                  style: TextStyle(
                    color: preview.isLive
                        ? const Color(0xFF156B51)
                        : const Color(0xFF153D69),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  )),
            ],
          ),
          const SizedBox(height: 8),
          Text('Check-in: ${_formatDateTime(preview.checkIn)}'),
          if (!preview.isLive && preview.checkOut != null)
            Text('Check-out: ${_formatDateTime(preview.checkOut!)}'),
          Text('Time: $elapsedText   ·   Billable: ${preview.billableHours} hr'),
          Text('Rate: @ ${formatAmount(preview.hourlyRate)}'),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(preview.isLive ? 'Estimated Room Charges' : 'Final Room Charges',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(formatMoney(preview.amount, currency),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ],
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
