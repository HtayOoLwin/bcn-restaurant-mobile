import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_config.dart';
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

class MenuScreen extends ConsumerWidget {
  const MenuScreen({super.key, required this.customer});

  final String customer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final menu = ref.watch(menuProvider);
    final cart = ref.watch(cartProvider);

    return Scaffold(
      appBar: AppBar(title: Text('Order - $customer')),
      body: menu.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text(error.toString())),
        data: (response) => ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
          children: [
            for (final group in response.groups) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(group, style: Theme.of(context).textTheme.titleLarge),
              ),
              ...response.items
                  .where((item) => item.itemGroup == group)
                  .map((item) => _MenuTile(item: item)),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: cart.lines.isEmpty ? null : () => context.go('/cart'),
            icon: const Icon(Icons.shopping_cart),
            label: Text(
              'Cart ${cart.totalQty.toStringAsFixed(0)}  •  ${cart.grandTotal.toStringAsFixed(0)}',
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
                  errorBuilder: (_, __, ___) => const Icon(Icons.restaurant, size: 40),
                ),
              )
            : const SizedBox(width: 56, child: Icon(Icons.restaurant, size: 40)),
        title: Text(item.itemName),
        subtitle: Text('${item.rate.toStringAsFixed(0)} ${item.currency} • ${item.uom}'),
        trailing: IconButton.filledTonal(
          tooltip: 'Add',
          onPressed: () => ref.read(cartProvider.notifier).add(item),
          icon: const Icon(Icons.add),
        ),
      ),
    );
  }
}
