class WaiterProgressItem {
  const WaiterProgressItem({
    required this.rowName,
    required this.itemName,
    required this.qty,
    required this.uom,
    required this.rate,
    required this.amount,
    required this.status,
    required this.canCancel,
    required this.cancelableQty,
    required this.printedQty,
    this.foc = false,
    this.parcel = false,
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
      rate: (json['rate'] as num?)?.toDouble() ?? 0,
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      status: json['status']?.toString() ?? 'New',
      canCancel: json['can_cancel'] == true,
      cancelableQty: (json['cancelable_qty'] as num?)?.toDouble() ?? 0,
      printedQty: (json['printed_qty'] as num?)?.toDouble() ?? 0,
      foc: json['custom_foc'] == true || json['custom_foc'] == 1 || json['custom_foc'] == '1',
      parcel: json['custom_parcel'] == true || json['custom_parcel'] == 1 || json['custom_parcel'] == '1',
      kitchenCounter: json['kitchen_counter']?.toString(),
      kitchenNote: json['kitchen_note']?.toString(),
    );
  }

  final String rowName;
  final String itemName;
  final double qty;
  final String uom;
  final double rate;
  final double amount;
  final String status;
  final bool canCancel;
  final double cancelableQty;
  final double printedQty;
  final bool foc;
  final bool parcel;
  final String? kitchenCounter;
  final String? kitchenNote;
}

class WaiterRoomPreview {
  const WaiterRoomPreview({
    required this.checkIn,
    required this.checkOut,
    required this.elapsedSeconds,
    required this.billableHours,
    required this.hourlyRate,
    required this.amount,
    required this.isLive,
  });

  factory WaiterRoomPreview.fromJson(Map<String, dynamic> json) =>
      WaiterRoomPreview(
        checkIn: json['check_in']?.toString() ?? '',
        checkOut: json['check_out']?.toString(),
        elapsedSeconds: (json['elapsed_seconds'] as num?)?.toDouble() ?? 0,
        billableHours: (json['billable_hours'] as num?)?.toDouble() ?? 0,
        hourlyRate: (json['hourly_rate'] as num?)?.toDouble() ?? 0,
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        isLive: json['is_live'] == true,
      );

  final String checkIn;
  final String? checkOut;
  final double elapsedSeconds;
  final double billableHours;
  final double hourlyRate;
  final double amount;
  final bool isLive;
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
    required this.billRevision,
    required this.netTotal,
    required this.taxesTotal,
    required this.grandTotal,
    required this.currency,
    required this.taxes,
    this.roomPreview,
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
      billRevision: (json['bill_revision'] as num?)?.toInt() ?? 0,
      netTotal: number('net_total'),
      taxesTotal: number('total_taxes_and_charges'),
      grandTotal: number('grand_total'),
      currency: json['currency']?.toString() ?? 'MMK',
      taxes: json['taxes'] as List? ?? const [],
      roomPreview: json['room_preview'] is Map
          ? WaiterRoomPreview.fromJson(
              Map<String, dynamic>.from(json['room_preview'] as Map),
            )
          : null,
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
  final int billRevision;
  final List<dynamic> taxes;
  final double netTotal;
  final double taxesTotal;
  final double grandTotal;
  final String currency;
  final WaiterRoomPreview? roomPreview;
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
