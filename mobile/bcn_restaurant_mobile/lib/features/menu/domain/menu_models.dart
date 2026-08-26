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
      groups: (json['groups'] as List? ?? const []).map((e) => e.toString()).toList(),
      items: (json['items'] as List? ?? const [])
          .map((row) => MenuItemModel.fromJson(Map<String, dynamic>.from(row as Map)))
          .toList(),
    );
  }

  final String priceList;
  final String currency;
  final List<String> groups;
  final List<MenuItemModel> items;
}
