import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_config.dart';
import '../../../core/formatters/amount_format.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../orders/data/orders_repository.dart';
import '../../waiter/presentation/waiter_tables_screen.dart';
import '../../waiter_progress/presentation/waiter_ready_screen.dart';
import '../domain/cart_controller.dart';

final ordersRepositoryProvider = Provider<OrdersRepository>(
  (ref) => OrdersRepository(ref.watch(apiClientProvider)),
);

class CartScreen extends ConsumerStatefulWidget {
  const CartScreen({super.key, this.embedded = false});
  final bool embedded;

  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen> {
  bool submitting = false;

  Future<void> _placeOrder() async {
    final cart = ref.read(cartProvider);
    if (cart.lines.isEmpty || submitting) return;

    setState(() => submitting = true);
    try {
      final result = await ref.read(ordersRepositoryProvider).createOrder(cart);
      ref.invalidate(tablesProvider('dine_in'));
      ref.invalidate(tablesProvider('takeaway'));
      ref.invalidate(waiterProgressProvider);
      ref.read(cartProvider.notifier).clear();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text(
            result.duplicate ? 'Order already received' : 'Order placed',
          ),
          content: Text(
            'Sales Order: ${result.salesOrder}\n'
            '${result.session.isNotEmpty ? 'Session: ${result.session}\n' : ''}'
            'Total: ${formatAmount(result.grandTotal)}',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (mounted) context.go('/tables');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    if (widget.embedded) return _buildDesktopCart(cart);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
        toolbarHeight: widget.embedded ? 56 : 72,
        leading: widget.embedded ? null : BackButton(
          onPressed: () {
            if (context.canPop()) {
              context.pop();
              return;
            }
            final customer = cart.customer;
            if (customer != null && customer.isNotEmpty) {
              context.go('/menu/${Uri.encodeComponent(customer)}');
              return;
            }
            context.go('/tables');
          },
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.embedded ? 'Current Order' : 'Cart - ${cart.customer ?? ''}',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 19),
            ),
            const SizedBox(height: 2),
            Text(
              '${formatQuantity(cart.totalQty)} item${cart.totalQty == 1 ? '' : 's'} selected',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.82),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          if (cart.lines.isNotEmpty)
            IconButton(
              tooltip: 'Clear cart',
              onPressed: () {
                final customer = cart.customer;
                final session = cart.session;
                ref.read(cartProvider.notifier).clear();
                if (widget.embedded && customer != null) {
                  ref.read(cartProvider.notifier).setOrderContext(customer: customer, session: session);
                }
              },
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          const SizedBox(width: 6),
        ],
      ),
      body: cart.lines.isEmpty
          ? const _EmptyCart()
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
              children: [
                for (final line in cart.lines) ...[
                  _CartLineCard(key: ValueKey('${line.item.itemCode}-${line.item.uom}-${line.foc}-${line.parcel}'), line: line),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 2),
                TextFormField(
                  initialValue: cart.remarks,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Order Note (Optional)',
                    prefixIcon: Icon(Icons.description_outlined),
                  ),
                  onChanged: ref.read(cartProvider.notifier).setRemarks,
                ),
                const SizedBox(height: 14),
                _TotalPanel(cart: cart),
              ],
            ),
      bottomNavigationBar: cart.lines.isEmpty
          ? null
          : SafeArea(
              top: false,
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: FilledButton.icon(
                  onPressed: submitting ? null : _placeOrder,
                  icon: submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send_rounded),
                  label: Text(
                    submitting ? 'Placing Order...' : 'Place Order',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ),
    );
  }
  Widget _buildDesktopCart(CartState cart) {
    final controller = ref.read(cartProvider.notifier);
    return Material(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            margin: const EdgeInsets.all(10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFFEAF1F8), borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              const Icon(Icons.shopping_cart_outlined, color: Color(0xFF1E5E96)),
              const SizedBox(width: 8),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Current Order', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                Text('${formatQuantity(cart.totalQty)} items selected', style: const TextStyle(fontSize: 12)),
              ])),
              IconButton(tooltip: 'Clear cart', onPressed: submitting || cart.lines.isEmpty ? null : () {
                final customer = cart.customer;
                final session = cart.session;
                controller.clear();
                if (customer != null) controller.setOrderContext(customer: customer, session: session);
              }, icon: const Icon(Icons.delete_outline, color: Color(0xFFC62828))),
            ]),
          ),
          Expanded(
            child: cart.lines.isEmpty ? const _EmptyCart() : ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              itemCount: cart.lines.length,
              separatorBuilder: (context, index) => const Divider(height: 12),
              itemBuilder: (context, index) {
                final line = cart.lines[index];
                final image = AppConfig.resolveAssetUrl(line.item.image);
                return Column(
                  key: ValueKey('${line.item.itemCode}-${line.item.uom}-${line.foc}-${line.parcel}'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SizedBox(width: 36, height: 42, child: image.hasScheme ? Image.network(image.toString(), fit: BoxFit.contain, errorBuilder: (_, _, _) => const Icon(Icons.restaurant_menu)) : const Icon(Icons.restaurant_menu)),
                      const SizedBox(width: 6),
                      Expanded(child: Text(line.item.itemName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                      const SizedBox(width: 4),
                      Text(formatAmount(line.amount), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF1E5E96))),
                    ]),
                    Row(children: [
                      IconButton(visualDensity: VisualDensity.compact, tooltip: 'Decrease', onPressed: submitting ? null : () => controller.decrement(line.item.itemCode, uom: line.item.uom, foc: line.foc, parcel: line.parcel), icon: const Icon(Icons.remove_circle_outline, size: 20)),
                      Text(formatQuantity(line.qty), style: const TextStyle(fontWeight: FontWeight.w700)),
                      IconButton(visualDensity: VisualDensity.compact, tooltip: 'Increase', onPressed: submitting ? null : () => controller.add(line.item, foc: line.foc, parcel: line.parcel), icon: const Icon(Icons.add_circle, size: 20, color: Color(0xFF1E5E96))),
                      Expanded(child: Text([line.item.uom, if (line.foc) 'FOC', if (line.parcel) 'Parcel'].join(' · '), style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis)),
                    ]),
                    TextFormField(
                      initialValue: line.kitchenNote,
                      enabled: !submitting,
                      style: const TextStyle(fontSize: 12),
                      decoration: const InputDecoration(hintText: 'Kitchen note', isDense: true, contentPadding: EdgeInsets.all(8)),
                      onChanged: (value) => controller.setKitchenNote(line.item.itemCode, value, uom: line.item.uom, foc: line.foc, parcel: line.parcel),
                    ),
                  ],
                );
              },
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextFormField(
                key: ValueKey(cart.clientOrderId),
                initialValue: cart.remarks,
                enabled: !submitting,
                decoration: const InputDecoration(hintText: 'Order Note (Optional)', isDense: true, prefixIcon: Icon(Icons.edit_note)),
                onChanged: controller.setRemarks,
              ),
              const SizedBox(height: 8),
              _TotalPanel(cart: cart),
              const SizedBox(height: 8),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF15803D)),
                onPressed: submitting || cart.lines.isEmpty ? null : _placeOrder,
                icon: const Icon(Icons.check),
                label: Text(submitting ? 'Placing Order...' : 'Place Order'),
              ),
            ]),
          ),
        ],
      ),
    );
  }

}

class _CartLineCard extends ConsumerWidget {
  const _CartLineCard({super.key, required this.line});

  final CartLine line;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final imageUri = AppConfig.resolveAssetUrl(line.item.image);
    final windows = Theme.of(context).platform == TargetPlatform.windows;
    final primary = windows ? const Color(0xFF15803D) : Theme.of(context).colorScheme.primary;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDCE7F1)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: MediaQuery.sizeOf(context).width >= 1200 && Theme.of(context).platform == TargetPlatform.windows ? 44 : 68,
                  height: MediaQuery.sizeOf(context).width >= 1200 && Theme.of(context).platform == TargetPlatform.windows ? 44 : 68,
                  color: const Color(0xFFEAF1F8),
                  child: imageUri.hasScheme
                      ? Image.network(
                          imageUri.toString(),
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const Icon(
                            Icons.restaurant_menu_rounded,
                            size: 32,
                            color: Color(0xFF5E7D9C),
                          ),
                        )
                      : const Icon(
                          Icons.restaurant_menu_rounded,
                          size: 32,
                          color: Color(0xFF5E7D9C),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      line.item.itemName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: const Color(0xFF102F4F),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (line.foc || line.parcel) ...[
                      const SizedBox(height: 4),
                      Text([if (line.foc) 'FOC', if (line.parcel) 'PARCEL'].join(' · '), style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF187C65))),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      '${formatMoney(line.foc ? 0 : line.item.rate, line.item.currency)} / ${line.item.uom}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF315F8E),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      formatMoney(line.amount, line.item.currency),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: const Color(0xFF102F4F),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton.filledTonal(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Decrease',
                    style: windows ? IconButton.styleFrom(backgroundColor: const Color(0xFFC62828), foregroundColor: Colors.white) : null,
                    onPressed: () => ref
                        .read(cartProvider.notifier)
                        .decrement(line.item.itemCode, uom: line.item.uom, foc: line.foc, parcel: line.parcel),
                    icon: const Icon(Icons.remove_rounded),
                  ),
                  SizedBox(
                    width: 28,
                    child: Text(
                      formatQuantity(line.qty),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF102F4F),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton.filled(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Increase',
                    style: IconButton.styleFrom(
                      backgroundColor: primary,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () =>
                        ref.read(cartProvider.notifier).add(line.item, foc: line.foc, parcel: line.parcel),
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextFormField(
            key: ValueKey('note-${line.item.itemCode}-${line.item.uom}-${line.foc}-${line.parcel}'),
            initialValue: line.kitchenNote,
            decoration: const InputDecoration(
              labelText: 'Kitchen note',
              prefixIcon: Icon(Icons.edit_note_rounded),
              isDense: true,
            ),
            onChanged: (value) => ref
                .read(cartProvider.notifier)
                .setKitchenNote(line.item.itemCode, value, uom: line.item.uom, foc: line.foc, parcel: line.parcel),
          ),
        ],
      ),
    );
  }
}

class _TotalPanel extends StatelessWidget {
  const _TotalPanel({required this.cart});

  final CartState cart;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFEAF1F8),
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              const Text(
                'Items',
                style: TextStyle(
                  color: Color(0xFF486987),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                formatQuantity(cart.totalQty),
                style: const TextStyle(
                  color: Color(0xFF173A5E),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                'Total',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: const Color(0xFF102F4F),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Text(
                formatAmount(cart.grandTotal),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: const Color(0xFF174F82),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyCart extends StatelessWidget {
  const _EmptyCart();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.shopping_cart_outlined,
            size: 54,
            color: Color(0xFF7892AA),
          ),
          const SizedBox(height: 12),
          Text(
            'Cart is empty',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: const Color(0xFF173A5E),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
