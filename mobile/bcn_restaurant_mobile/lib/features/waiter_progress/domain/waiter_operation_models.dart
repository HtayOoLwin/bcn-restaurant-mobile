class WaiterProgressItem {
  const WaiterProgressItem({
    required this.rowName,
    required this.itemName,
    required this.qty,
    required this.uom,
    required this.status,
    required this.canCancel,
    this.kitchenCounter,
    this.kitchenNote,
  });

  factory WaiterProgressItem.fromJson(Map<String, dynamic> json) {
    return WaiterProgressItem(
      rowName: json['row_name']?.toString() ?? '',
      itemName:
          json['item_name']?.toString() ?? json['item_code']?.toString() ?? '',
      qty: (json['qty'] as num?)?.toDouble() ?? 0,
      uom: json['uom']?.toString() ?? '',
      status: json['status']?.toString() ?? 'New',
      canCancel: json['can_cancel'] == true,
      kitchenCounter: json['kitchen_counter']?.toString(),
      kitchenNote: json['kitchen_note']?.toString(),
    );
  }

  final String rowName;
  final String itemName;
  final double qty;
  final String uom;
  final String status;
  final bool canCancel;
  final String? kitchenCounter;
  final String? kitchenNote;
}

class WaiterProgressOrder {
  const WaiterProgressOrder({
    required this.name,
    required this.customer,
    required this.preparationSummary,
    required this.items,
    required this.newQty,
    required this.preparingQty,
    required this.readyQty,
    required this.servedQty,
  });

  factory WaiterProgressOrder.fromJson(Map<String, dynamic> json) {
    double number(String key) => (json[key] as num?)?.toDouble() ?? 0;
    return WaiterProgressOrder(
      name: json['name']?.toString() ?? '',
      customer:
          json['customer_name']?.toString() ??
          json['customer']?.toString() ??
          '',
      preparationSummary: json['preparation_summary']?.toString() ?? 'New',
      items: (json['items'] as List? ?? const [])
          .map(
            (row) => WaiterProgressItem.fromJson(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList(),
      newQty: number('new_qty'),
      preparingQty: number('preparing_qty'),
      readyQty: number('ready_qty'),
      servedQty: number('served_qty'),
    );
  }

  final String name;
  final String customer;
  final String preparationSummary;
  final List<WaiterProgressItem> items;
  final double newQty;
  final double preparingQty;
  final double readyQty;
  final double servedQty;
}

class WaiterProgressResponse {
  const WaiterProgressResponse({required this.orders});

  factory WaiterProgressResponse.fromJson(Map<String, dynamic> json) {
    return WaiterProgressResponse(
      orders: (json['orders'] as List? ?? const [])
          .map(
            (row) => WaiterProgressOrder.fromJson(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList(),
    );
  }

  final List<WaiterProgressOrder> orders;
}

class WaiterReadyItem {
  const WaiterReadyItem({
    required this.rowName,
    required this.itemName,
    required this.qty,
    required this.uom,
    this.kitchenCounter,
    this.kitchenNote,
  });

  factory WaiterReadyItem.fromJson(Map<String, dynamic> json) {
    return WaiterReadyItem(
      rowName: json['row_name']?.toString() ?? '',
      itemName:
          json['item_name']?.toString() ?? json['item_code']?.toString() ?? '',
      qty: (json['qty'] as num?)?.toDouble() ?? 0,
      uom: json['uom']?.toString() ?? '',
      kitchenCounter: json['kitchen_counter']?.toString(),
      kitchenNote: json['kitchen_note']?.toString(),
    );
  }

  final String rowName;
  final String itemName;
  final double qty;
  final String uom;
  final String? kitchenCounter;
  final String? kitchenNote;
}

class WaiterReadyOrder {
  const WaiterReadyOrder({
    required this.name,
    required this.customer,
    required this.canServeWhole,
    required this.items,
  });

  factory WaiterReadyOrder.fromJson(Map<String, dynamic> json) {
    return WaiterReadyOrder(
      name: json['name']?.toString() ?? '',
      customer: json['customer']?.toString() ?? '',
      canServeWhole: json['can_serve_whole'] == true,
      items: (json['items'] as List? ?? const [])
          .map(
            (row) =>
                WaiterReadyItem.fromJson(Map<String, dynamic>.from(row as Map)),
          )
          .toList(),
    );
  }

  final String name;
  final String customer;
  final bool canServeWhole;
  final List<WaiterReadyItem> items;
}

class WaiterReadyResponse {
  const WaiterReadyResponse({required this.orders});

  factory WaiterReadyResponse.fromJson(Map<String, dynamic> json) {
    return WaiterReadyResponse(
      orders: (json['orders'] as List? ?? const [])
          .map(
            (row) => WaiterReadyOrder.fromJson(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList(),
    );
  }

  final List<WaiterReadyOrder> orders;
}
