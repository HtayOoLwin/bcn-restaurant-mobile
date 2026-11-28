import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatters/amount_format.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/offline_sync_service.dart';
import '../../cart/presentation/cart_screen.dart';
import '../../waiter/presentation/waiter_tables_screen.dart';
import '../../waiter_progress/presentation/waiter_ready_screen.dart';
import '../../cashier/presentation/cashier_screen.dart';

final _offlineOrdersProvider = FutureProvider.autoDispose<Map<String, String>>(
  (ref) => ref.watch(apiClientProvider).pendingOrders(),
);

class OfflineOrdersScreen extends ConsumerStatefulWidget {
  const OfflineOrdersScreen({super.key});

  @override
  ConsumerState<OfflineOrdersScreen> createState() => _OfflineOrdersScreenState();
}

class _OfflineOrdersScreenState extends ConsumerState<OfflineOrdersScreen> {
  String? selected;

  @override
  Widget build(BuildContext context) {
    final records = ref.watch(_offlineOrdersProvider);
    final sync = ref.watch(offlineSyncProvider);
    ref.listen(offlineSyncProvider, (previous, next) {
      if (previous?.running == true && !next.running) {
        ref.invalidate(_offlineOrdersProvider);
        ref.invalidate(pendingOrderCountProvider);
        ref.invalidate(tablesProvider);
        ref.invalidate(waiterProgressProvider);
        ref.invalidate(waiterReadyProvider);
        ref.invalidate(cashierBillingProvider);
      }
    });
    return Scaffold(
      appBar: AppBar(
        title: const Text('Offline Orders'),
        actions: [
          TextButton.icon(
            onPressed: sync.running || (records.asData?.value.isEmpty ?? true)
                ? null : () async { await ref.read(offlineSyncProvider.notifier).sync(); },
            icon: const Icon(Icons.sync),
            label: Text(sync.running ? 'Syncing…' : 'Sync Now'),
          ),
          IconButton(tooltip: 'Refresh', onPressed: () => ref.invalidate(_offlineOrdersProvider), icon: const Icon(Icons.refresh)),
        ],
      ),
      body: records.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Unable to read local orders: $error')),
        data: (records) {
          final orders = records.entries.map(_LocalOrder.fromEntry).toList()
            ..sort((a, b) => b.created.compareTo(a.created));
          if (orders.isEmpty) {
            return Center(child: Text(sync.completed > 0
                ? '${sync.completed} order(s) synced. No pending orders.'
                : 'No pending offline orders'));
          }
          final order = orders.firstWhere((o) => o.id == selected, orElse: () => orders.first);
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: const Color(0xFFFCE7E8), borderRadius: BorderRadius.circular(8)),
                  child: Text('${orders.length} pending orders · Not sent to ERPNext or kitchen',
                    style: const TextStyle(color: Color(0xFFB4232D), fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 10),
                Expanded(child: Row(children: [
                  Expanded(flex: 2, child: Card(
                    color: Colors.white,
                    child: ListView.separated(
                      itemCount: orders.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final entry = orders[index];
                        return ListTile(
                          selected: entry.id == order.id,
                          selectedTileColor: const Color(0xFFE3EFFC),
                          leading: const Icon(Icons.receipt_long_outlined),
                          title: Text(entry.customer, style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(entry.dateLabel),
                          trailing: Text(entry.valid ? formatAmount(entry.total) : 'Unreadable'),
                          onTap: () => setState(() => selected = entry.id),
                        );
                      },
                    ),
                  )),
                  const SizedBox(width: 10),
                  Expanded(flex: 3, child: Card(
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(order.customer, style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 5),
                          SelectableText('Local ID: ${order.id}', style: const TextStyle(fontSize: 11)),
                          Text(order.dateLabel),
                          if (sync.errors[order.id] != null || sync.errors['_sync'] != null)
                            Text(sync.errors[order.id] ?? sync.errors['_sync']!, style: const TextStyle(color: Color(0xFFB4232D), fontWeight: FontWeight.w700)),
                          const Divider(),
                          if (!order.valid) const Expanded(child: Center(child: Text('Record could not be decoded. It has not been deleted.')))
                          else ...[
                            const Row(children: [
                              Expanded(flex: 4, child: Text('Item / UOM', style: TextStyle(fontWeight: FontWeight.w700))),
                              Expanded(child: Text('Qty', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w700))),
                            ]),
                            const Divider(),
                            Expanded(child: ListView.separated(
                              itemCount: order.items.length,
                              separatorBuilder: (_, _) => const Divider(height: 12),
                              itemBuilder: (_, index) {
                                final item = order.items[index];
                                final tags = [
                                  item['uom']?.toString() ?? '',
                                  if (item['foc'] == 1) 'FOC',
                                  if (item['parcel'] == 1) 'Parcel',
                                ].where((s) => s.isNotEmpty).join(' · ');
                                return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Expanded(flex: 4, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(item['item_name']?.toString() ?? item['item_code']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                                    Text(tags, style: const TextStyle(fontSize: 12)),
                                    if ((item['kitchen_note']?.toString() ?? '').isNotEmpty)
                                      Text('Kitchen note: ${item['kitchen_note']}'),
                                  ])),
                                  Expanded(child: Text(item['qty']?.toString() ?? '', textAlign: TextAlign.right)),
                                ]);
                              },
                            )),
                            if (order.remarks.isNotEmpty) Text('Order note: ${order.remarks}'),
                            const Divider(),
                            Row(children: [
                              const Expanded(child: Text('Estimated Total', style: TextStyle(fontWeight: FontWeight.w700))),
                              Text(formatAmount(order.total), style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF155484), fontSize: 18)),
                            ]),
                            const SizedBox(height: 8),
                            const Text('Pending Sync · Printing not available yet', style: TextStyle(color: Color(0xFFB4232D), fontWeight: FontWeight.w700)),
                          ],
                        ],
                      ),
                    ),
                  )),
                ])),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _LocalOrder {
  const _LocalOrder(this.id, this.customer, this.created, this.total, this.items, this.remarks, this.valid);
  final String id;
  final String customer;
  final String created;
  final double total;
  final List<Map<String, dynamic>> items;
  final String remarks;
  final bool valid;

  String get dateLabel {
    final date = DateTime.tryParse(created)?.toLocal();
    return date == null ? created : date.toString().split('.').first;
  }

  factory _LocalOrder.fromEntry(MapEntry<String, String> entry) {
    try {
      final record = jsonDecode(entry.value) as Map;
      final payload = record['payload'] as Map;
      final raw = record['display_items'] ?? payload['items'];
      final items = (raw is String ? jsonDecode(raw) : raw) as List;
      return _LocalOrder(entry.key, payload['customer']?.toString() ?? 'Unknown table',
        record['created_at']?.toString() ?? '', (record['estimated_total'] as num?)?.toDouble() ?? 0,
        items.map((item) => Map<String, dynamic>.from(item as Map)).toList(),
        payload['remarks']?.toString() ?? '', true);
    } catch (_) {
      return _LocalOrder(entry.key, 'Unreadable local order', '', 0, const [], '', false);
    }
  }
}
