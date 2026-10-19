class MenuUomOption {
  const MenuUomOption({
    required this.uom,
    required this.rate,
    required this.conversionFactor,
  });

  final String uom;
  final double rate;
  final double conversionFactor;

  factory MenuUomOption.fromJson(Map<String, dynamic> json) => MenuUomOption(
    uom: json['uom']?.toString() ?? '',
    rate: (json['rate'] as num?)?.toDouble() ?? 0,
    conversionFactor: (json['conversion_factor'] as num?)?.toDouble() ?? 1,
  );
}

class MenuItemModel {
  const MenuItemModel({
    required this.itemCode,
    required this.itemName,
    required this.itemGroup,
    required this.uom,
    required this.rate,
    required this.currency,
    required this.isStockItem,
    this.image,
    this.kitchenCounter,
    this.uoms = const [],
  });

  factory MenuItemModel.fromJson(Map<String, dynamic> json) {
    return MenuItemModel(
      itemCode: json['item_code']?.toString() ?? '',
      itemName: json['item_name']?.toString() ?? '',
      itemGroup: json['item_group']?.toString() ?? '',
      uom: json['uom']?.toString() ?? '',
      rate: (json['rate'] as num?)?.toDouble() ?? 0,
      currency: json['currency']?.toString() ?? '',
      isStockItem: json['is_stock_item'] == true,
      image: json['image']?.toString(),
      kitchenCounter: json['kitchen_counter']?.toString(),
      uoms: (json['uoms'] as List? ?? const [])
          .map((value) => MenuUomOption.fromJson(Map<String, dynamic>.from(value as Map)))
          .toList(),
    );
  }

  final String itemCode;
  final String itemName;
  final String itemGroup;
  final String uom;
  final double rate;
  final String currency;
  final bool isStockItem;
  final String? image;
  final String? kitchenCounter;
  final List<MenuUomOption> uoms;

  List<MenuUomOption> get availableUoms => uoms.isEmpty
      ? [MenuUomOption(uom: uom, rate: rate, conversionFactor: 1)]
      : uoms;

  MenuItemModel withUom(MenuUomOption selected) => MenuItemModel(
    itemCode: itemCode,
    itemName: itemName,
    itemGroup: itemGroup,
    uom: selected.uom,
    rate: selected.rate,
    currency: currency,
    isStockItem: isStockItem,
    image: image,
    kitchenCounter: kitchenCounter,
    uoms: uoms,
  );
}

class MenuResponse {
  const MenuResponse({
    required this.priceList,
    required this.currency,
    required this.groups,
    required this.items,
  });

  factory MenuResponse.fromJson(Map<String, dynamic> json) {
    return MenuResponse(
      priceList: json['price_list']?.toString() ?? '',
      currency: json['currency']?.toString() ?? '',
      groups: (json['groups'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(),
      items: (json['items'] as List? ?? const [])
          .map(
            (row) =>
                MenuItemModel.fromJson(Map<String, dynamic>.from(row as Map)),
          )
          .toList(),
    );
  }

  final String priceList;
  final String currency;
  final List<String> groups;
  final List<MenuItemModel> items;
}
