import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_config.dart';
import '../../../core/formatters/amount_format.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../cart/domain/cart_controller.dart';
import '../data/menu_repository.dart';
import '../domain/menu_models.dart';

final menuRepositoryProvider = Provider<MenuRepository>(
  (ref) => MenuRepository(ref.watch(apiClientProvider)),
);

final menuProvider = FutureProvider<MenuResponse>(
  (ref) => ref.watch(menuRepositoryProvider).getMenu(),
);

class MenuScreen extends ConsumerStatefulWidget {
  const MenuScreen({super.key, required this.customer});

  final String customer;

  @override
  ConsumerState<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends ConsumerState<MenuScreen> {
  String _selectedCategory = 'All';

  @override
  Widget build(BuildContext context) {
    final menu = ref.watch(menuProvider);
    final cart = ref.watch(cartProvider);

    return Scaffold(
      appBar: AppBar(title: Text('Order - ${widget.customer}')),
      body: menu.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text(error.toString())),
        data: (response) {
          final categories = <String>['All', ...response.groups];
          final visibleItems = _selectedCategory == 'All'
              ? response.items
              : response.items
                    .where((item) => item.itemGroup == _selectedCategory)
                    .toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final category in categories) ...[
                        ChoiceChip(
                          label: Text(category),
                          selected: _selectedCategory == category,
                          onSelected: (_) =>
                              setState(() => _selectedCategory = category),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
              ),
              Expanded(
                child: visibleItems.isEmpty
                    ? const Center(child: Text('No items in this category.'))
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                        children: [
                          ...visibleItems.map((item) => _MenuTile(item: item)),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: cart.lines.isEmpty ? null : () => context.push('/cart'),
            icon: const Icon(Icons.shopping_cart),
            label: Text(
              'Cart ${formatQuantity(cart.totalQty)}  •  ${formatAmount(cart.grandTotal)}',
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuTile extends ConsumerWidget {
  const _MenuTile({required this.item});

  final MenuItemModel item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final imageUri = AppConfig.resolveAssetUrl(item.image);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: imageUri.hasScheme
            ? ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  imageUri.toString(),
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      const Icon(Icons.restaurant, size: 40),
                ),
              )
            : const SizedBox(
                width: 56,
                child: Icon(Icons.restaurant, size: 40),
              ),
        title: Text(item.itemName),
        subtitle: Text(
          '${formatMoney(item.rate, item.currency)} • ${item.uom}',
        ),
        trailing: _QuantityControl(item: item),
      ),
    );
  }
}

class _QuantityControl extends ConsumerWidget {
  const _QuantityControl({required this.item});

  final MenuItemModel item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    var quantity = 0.0;
    for (final line in cart.lines) {
      if (line.item.itemCode == item.itemCode) {
        quantity = line.qty;
        break;
      }
    }

    if (quantity <= 0) {
      return IconButton.filledTonal(
        tooltip: 'Add',
        onPressed: () => ref.read(cartProvider.notifier).add(item),
        icon: const Icon(Icons.add),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: 'Decrease',
          onPressed: () =>
              ref.read(cartProvider.notifier).decrement(item.itemCode),
          icon: const Icon(Icons.remove),
        ),
        Text(
          formatQuantity(quantity),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: 'Increase',
          onPressed: () => ref.read(cartProvider.notifier).add(item),
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }
}
