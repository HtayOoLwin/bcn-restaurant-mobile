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
  String _searchQuery = '';
  final _searchController = TextEditingController();
  bool _addingRoomCharge = false;

  Future<void> _selectRoomCharge(List<MenuItemModel> items) async {
    if (_addingRoomCharge) return;
    final selected = await showDialog<MenuItemModel>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Select Room Charges Item'),
        content: SizedBox(
          width: double.maxFinite,
          height: 330,
          child: ListView(
            shrinkWrap: true,
            children: items.where((item) => !item.isStockItem).map((item) =>
              ListTile(
                title: Text(item.itemName),
                subtitle: Text('${item.itemCode} · ${formatMoney(item.rate, item.currency)} / ${item.uom}'),
                onTap: () => Navigator.pop(dialogContext, item),
              ),
            ).toList(),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel'))],
      ),
    );
    if (selected == null || !mounted) return;
    setState(() => _addingRoomCharge = true);
    try {
      await ref.read(apiClientProvider).postMethod(
        'bcn_set_room_charge',
        data: {'customer': widget.customer, 'item_code': selected.itemCode},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Room Charges selected: ${selected.itemName}')),
      );
      ref.invalidate(menuProvider);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _addingRoomCharge = false);
    }
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.invalidate(menuProvider);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final menu = ref.watch(menuProvider);
    final cart = ref.watch(cartProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.customer,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
            ),
            const SizedBox(height: 2),
            Text(
              'Select menu items',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.82),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      body: menu.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(error.toString(), textAlign: TextAlign.center),
          ),
        ),
        data: (response) {
          final categories = <String>['All', ...response.groups];
          final normalizedQuery = _searchQuery.trim().toLowerCase();
          final visibleItems = response.items.where((item) {
            final matchesCategory =
                _selectedCategory == 'All' ||
                item.itemGroup == _selectedCategory;
            final matchesSearch =
                normalizedQuery.isEmpty ||
                item.itemName.toLowerCase().contains(normalizedQuery) ||
                item.itemCode.toLowerCase().contains(normalizedQuery);
            return matchesCategory && matchesSearch;
          }).toList();

          return Column(
            children: [
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: TextField(
                  controller: _searchController,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search menu items',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _searchQuery.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            icon: const Icon(Icons.clear_rounded),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          ),
                    isDense: true,
                  ),
                  onChanged: (value) => setState(() => _searchQuery = value),
                ),
              ),
              Container(
                width: double.infinity,
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(12, 2, 12, 12),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final category in categories) ...[
                        ChoiceChip(
                          label: Text(category),
                          selected: _selectedCategory == category,
                          showCheckmark: false,
                          selectedColor: colorScheme.primary,
                          backgroundColor: const Color(0xFFEAF1F8),
                          side: BorderSide.none,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          labelStyle: TextStyle(
                            color: _selectedCategory == category
                                ? Colors.white
                                : const Color(0xFF173A5E),
                            fontWeight: FontWeight.w700,
                          ),
                          onSelected: (_) =>
                              setState(() => _selectedCategory = category),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: OutlinedButton.icon(
                  onPressed: _addingRoomCharge ? null : () => _selectRoomCharge(response.items),
                  icon: const Icon(Icons.meeting_room_outlined),
                  label: Text(_addingRoomCharge ? 'Saving Room Charges...' : 'Add Room Charges'),
                ),
              ),
              Expanded(
                child: visibleItems.isEmpty
                    ? Center(
                        child: Text(
                          normalizedQuery.isEmpty
                              ? 'No items in this category.'
                              : 'No matching items.',
                          style: const TextStyle(color: Color(0xFF66829D)),
                        ),
                      )
                    : ListView.separated(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 110),
                        itemCount: visibleItems.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 9),
                        itemBuilder: (context, index) =>
                            _MenuItemCard(
                              key: ValueKey(visibleItems[index].itemCode),
                              item: visibleItems[index],
                            ),
                      ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: FilledButton(
            onPressed: cart.lines.isEmpty
                ? null
                : () async {
                    await context.push('/cart');
                    if (!mounted) return;
                    ref.invalidate(menuProvider);
                  },
            child: Row(
              children: [
                const Icon(Icons.shopping_cart_outlined),
                const SizedBox(width: 10),
                const Text(
                  'View Cart',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                if (cart.lines.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      formatQuantity(cart.totalQty),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
                const Spacer(),
                Text(
                  formatAmount(cart.grandTotal),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuItemCard extends ConsumerStatefulWidget {
  const _MenuItemCard({super.key, required this.item});

  final MenuItemModel item;

  @override
  ConsumerState<_MenuItemCard> createState() => _MenuItemCardState();
}

class _MenuItemCardState extends ConsumerState<_MenuItemCard> {
  String? _selectedUom;

  @override
  void didUpdateWidget(covariant _MenuItemCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.itemCode != widget.item.itemCode) {
      _selectedUom = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final imageUri = AppConfig.resolveAssetUrl(item.image);
    final cart = ref.watch(cartProvider);
    final options = item.availableUoms;
    final hasMultipleUoms = options.length > 1;
    final selected = options.firstWhere(
      (option) => option.uom == (_selectedUom ?? item.uom),
      orElse: () => options.first,
    );
    final selectedItem = item.withUom(selected);
    final quantity = cart.lines
        .where((line) =>
            line.item.itemCode == item.itemCode &&
            line.item.uom == selected.uom)
        .fold<double>(0, (sum, line) => sum + line.qty);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDCE7F1)),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 74,
                  height: 74,
                  color: const Color(0xFFEAF1F8),
                  child: imageUri.hasScheme
                      ? Image.network(
                          imageUri.toString(),
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const Icon(
                            Icons.restaurant_menu_rounded,
                            size: 34,
                            color: Color(0xFF5E7D9C),
                          ),
                        )
                      : const Icon(
                          Icons.restaurant_menu_rounded,
                          size: 34,
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
                      item.itemName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: const Color(0xFF102F4F),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.itemGroup,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF66829D),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${formatMoney(selected.rate, item.currency)} / ${selected.uom}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF173A5E),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (!hasMultipleUoms)
                _QuantityControl(item: selectedItem, quantity: quantity)
              else
                SizedBox(
                  width: 132,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _QuantityControl(item: selectedItem, quantity: quantity),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                    key: ValueKey('${item.itemCode}-${selected.uom}'),
                    initialValue: selected.uom,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'UOM',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    items: [
                      for (final option in options)
                        DropdownMenuItem(
                          value: option.uom,
                          child: Text(
                            option.uom,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _selectedUom = value);
                          }
                        },
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuantityControl extends ConsumerWidget {
  const _QuantityControl({required this.item, required this.quantity});

  final MenuItemModel item;
  final double quantity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final primary = Theme.of(context).colorScheme.primary;

    if (quantity <= 0) {
      return IconButton.filled(
        tooltip: 'Add',
        style: IconButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
        ),
        onPressed: () => ref.read(cartProvider.notifier).add(item),
        icon: const Icon(Icons.add_rounded),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filledTonal(
          visualDensity: VisualDensity.compact,
          tooltip: 'Decrease',
          onPressed: () =>
              ref.read(cartProvider.notifier).decrement(item.itemCode, uom: item.uom),
          icon: const Icon(Icons.remove_rounded),
        ),
        SizedBox(
          width: 28,
          child: Text(
            formatQuantity(quantity),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: const Color(0xFF102F4F),
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
          onPressed: () => ref.read(cartProvider.notifier).add(item),
          icon: const Icon(Icons.add_rounded),
        ),
      ],
    );
  }
}
