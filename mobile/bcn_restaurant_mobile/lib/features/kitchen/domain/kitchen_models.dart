class KitchenOrderItem {
  const KitchenOrderItem({
    required this.rowName,
    required this.itemCode,
    required this.itemName,
    required this.qty,
    required this.uom,
    required this.kitchenCounter,
    required this.preparationStatus,
    this.kitchenNote,
    this.createdAt,
  });

  factory KitchenOrderItem.fromJson(Map<String, dynamic> json) {
    return KitchenOrderItem(
      rowName: json['row_name']?.toString() ?? '',
      itemCode: json['item_code']?.toString() ?? '',
      itemName: json['item_name']?.toString() ?? json['item_code']?.toString() ?? '',
      qty: (json['qty'] as num?)?.toDouble() ?? 0,
      uom: json['uom']?.toString() ?? '',
      kitchenCounter: json['kitchen_counter']?.toString() ?? '',
      preparationStatus: json['preparation_status']?.toString() ?? 'New',
      kitchenNote: json['kitchen_note']?.toString(),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
    );
  }

  final String rowName;
  final String itemCode;
  final String itemName;
  final double qty;
  final String uom;
  final String kitchenCounter;
  final String preparationStatus;
  final String? kitchenNote;
  final DateTime? createdAt;

  String? get nextAction => switch (preparationStatus) {
        'New' => 'Accept',
        'Accepted' => 'Start Preparation',
        'Preparing' => 'Mark Ready',
        _ => null,
      };
}

class KitchenOrder {
  const KitchenOrder({
    required this.name,
    required this.customer,
    required this.preparationSummary,
    required this.items,
    this.session,
    this.creation,
  });

  factory KitchenOrder.fromJson(Map<String, dynamic> json) {
    return KitchenOrder(
      name: json['name']?.toString() ?? '',
      customer: json['customer']?.toString() ?? '',
      session: json['session']?.toString(),
      creation: DateTime.tryParse(json['creation']?.toString() ?? ''),
      preparationSummary: json['preparation_summary']?.toString() ?? 'New',
      items: (json['items'] as List? ?? const [])
          .map((row) => KitchenOrderItem.fromJson(Map<String, dynamic>.from(row as Map)))
          .toList(),
    );
  }

  final String name;
  final String customer;
  final String? session;
  final DateTime? creation;
  final String preparationSummary;
  final List<KitchenOrderItem> items;
}

class KitchenOrdersResponse {
  const KitchenOrdersResponse({required this.orders, required this.allowedCounters});

  factory KitchenOrdersResponse.fromJson(Map<String, dynamic> json) {
    return KitchenOrdersResponse(
      orders: (json['orders'] as List? ?? const [])
          .map((row) => KitchenOrder.fromJson(Map<String, dynamic>.from(row as Map)))
          .toList(),
      allowedCounters: (json['allowed_counters'] as List? ?? const [])
          .map((value) => value.toString())
          .toList(),
    );
  }

  final List<KitchenOrder> orders;
  final List<String> allowedCounters;
}
