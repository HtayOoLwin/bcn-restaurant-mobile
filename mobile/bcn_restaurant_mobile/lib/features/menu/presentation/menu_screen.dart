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

  Future<void> _selectRoomCharge(List<MenuItemModel> items) async {
    final roomItems = items.where((item) =>
        item.itemGroup.trim().toLowerCase() == 'room charges' &&
        !item.isStockItem).toList();
    if (roomItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No items found in Room Charges item group.')),
      );
      return;
    }
    final selected = await showDialog<MenuItemModel>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Select Room Charges Item'),
        content: SizedBox(
          width: double.maxFinite,
          height: 330,
          child: ListView(
            shrinkWrap: true,
            children: roomItems.map((item) =>
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
    ref.read(cartProvider.notifier).setOrderContext(customer: widget.customer);
    ref.read(cartProvider.notifier).selectRoomCharge(selected);

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
        title: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.customer,
                    overflow: TextOverflow.ellipsis,
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
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: menu.asData == null
                  ? null
                  : () => _selectRoomCharge(menu.asData!.value.items),
              icon: const Icon(Icons.meeting_room_outlined, size: 18),
              label: const Text('Room Charges'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFED9418),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFB7A186),
                disabledForegroundColor: Colors.white70,
                elevation: 1,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                shape: const StadiumBorder(),
                textStyle: const TextStyle(fontWeight: FontWeight.w700),
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
  bool _foc = false;
  bool _parcel = false;

  @override
  void didUpdateWidget(covariant _MenuItemCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.itemCode != widget.item.itemCode) {
      _selectedUom = null;
      _foc = false;
      _parcel = false;
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
            line.item.uom == selected.uom && line.foc == _foc && line.parcel == _parcel)
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
                _QuantityControl(item: selectedItem, quantity: quantity, foc: _foc, parcel: _parcel)
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
          if (item.itemGroup.trim().toLowerCase() != 'room charges') ...[
            const SizedBox(height: 8),
            Row(children: [
              FilterChip(label: const Text('FOC'), selected: _foc,
                avatar: const Icon(Icons.card_giftcard_outlined, size: 17),
                onSelected: (value) => setState(() => _foc = value)),
              const SizedBox(width: 8),
              FilterChip(label: const Text('Parcel'), selected: _parcel,
                avatar: const Icon(Icons.shopping_bag_outlined, size: 17),
                onSelected: (value) => setState(() => _parcel = value)),
              if (_foc) ...[
                const SizedBox(width: 8),
                const Text('0 MMK', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w700)),
              ],
            ]),
          ],
        ],
      ),
    );
  }
}

class _QuantityControl extends ConsumerWidget {
  const _QuantityControl({required this.item, required this.quantity, required this.foc, required this.parcel});

  final MenuItemModel item;
  final double quantity;
  final bool foc;
  final bool parcel;

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
        onPressed: () => ref.read(cartProvider.notifier).add(item, foc: foc, parcel: parcel),
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
              ref.read(cartProvider.notifier).decrement(item.itemCode, uom: item.uom, foc: foc, parcel: parcel),
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
          onPressed: () => ref.read(cartProvider.notifier).add(item, foc: foc, parcel: parcel),
          icon: const Icon(Icons.add_rounded),
        ),
      ],
    );
  }
}
