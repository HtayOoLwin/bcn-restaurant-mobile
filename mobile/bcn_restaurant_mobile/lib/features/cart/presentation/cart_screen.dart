import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/presentation/auth_controller.dart';
import '../../orders/data/orders_repository.dart';
import '../domain/cart_controller.dart';

final ordersRepositoryProvider = Provider<OrdersRepository>(
  (ref) => OrdersRepository(ref.watch(apiClientProvider)),
);

class CartScreen extends ConsumerStatefulWidget {
  const CartScreen({super.key});

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
      ref.read(cartProvider.notifier).clear();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text(result.duplicate ? 'Order already received' : 'Order placed'),
          content: Text(
            'Sales Order: ${result.salesOrder}\n'
            'Session: ${result.session}\n'
            'Total: ${result.grandTotal.toStringAsFixed(0)}',
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    return Scaffold(
      appBar: AppBar(title: Text('Cart - ${cart.customer ?? ''}')),
      body: cart.lines.isEmpty
          ? const Center(child: Text('Cart is empty'))
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 140),
              itemCount: cart.lines.length + 1,
              itemBuilder: (context, index) {
                if (index == cart.lines.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: TextFormField(
                      initialValue: cart.remarks,
                      decoration: const InputDecoration(
                        labelText: 'Order note (optional)',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: ref.read(cartProvider.notifier).setRemarks,
                    ),
                  );
                }
                final line = cart.lines[index];
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(line.item.itemName, style: Theme.of(context).textTheme.titleMedium),
                            ),
                            IconButton(
                              onPressed: () => ref.read(cartProvider.notifier).decrement(line.item.itemCode),
                              icon: const Icon(Icons.remove_circle_outline),
                            ),
                            Text(line.qty.toStringAsFixed(0)),
                            IconButton(
                              onPressed: () => ref.read(cartProvider.notifier).add(line.item),
                              icon: const Icon(Icons.add_circle_outline),
                            ),
                          ],
                        ),
                        Text('${line.amount.toStringAsFixed(0)} ${line.item.currency}'),
                        const SizedBox(height: 8),
                        TextFormField(
                          key: ValueKey('note-${line.item.itemCode}'),
                          initialValue: line.kitchenNote,
                          decoration: const InputDecoration(
                            labelText: 'Kitchen note',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (value) => ref
                              .read(cartProvider.notifier)
                              .setKitchenNote(line.item.itemCode, value),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Total: ${cart.grandTotal.toStringAsFixed(0)}',
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: cart.lines.isEmpty || submitting ? null : _placeOrder,
                child: submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Place Order'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
