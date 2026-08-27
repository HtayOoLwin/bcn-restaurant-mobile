class KitchenPrinterSettings {
  const KitchenPrinterSettings({
    required this.counterName,
    required this.printerIp,
    required this.printerPort,
    required this.paperWidth,
  });

  factory KitchenPrinterSettings.fromJson(Map<String, dynamic> json) {
    return KitchenPrinterSettings(
      counterName: json['counter_name']?.toString() ?? json['name']?.toString() ?? '',
      printerIp: json['printer_ip']?.toString().trim() ?? '',
      printerPort: (json['printer_port'] as num?)?.toInt() ?? 9100,
      paperWidth: json['paper_width']?.toString() ?? '80mm',
    );
  }

  final String counterName;
  final String printerIp;
  final int printerPort;
  final String paperWidth;

  bool get isConfigured => printerIp.isNotEmpty && printerPort > 0;
}

class KitchenPrintState {
  const KitchenPrintState({
    required this.printCount,
    this.lastPrintedAt,
    this.lastPrintedBy,
  });

  factory KitchenPrintState.fromJson(Map<String, dynamic> json) {
    return KitchenPrintState(
      printCount: (json['print_count'] as num?)?.toInt() ?? 0,
      lastPrintedAt: DateTime.tryParse(json['last_printed_at']?.toString() ?? ''),
      lastPrintedBy: json['last_printed_by']?.toString(),
    );
  }

  final int printCount;
  final DateTime? lastPrintedAt;
  final String? lastPrintedBy;
}

class KitchenPrintSnapshot {
  const KitchenPrintSnapshot({
    required this.counterSettings,
    required this.printState,
  });

  factory KitchenPrintSnapshot.fromJson(Map<String, dynamic> json) {
    final rawState = Map<String, dynamic>.from(json['print_state'] as Map? ?? const {});
    return KitchenPrintSnapshot(
      counterSettings: (json['counter_settings'] as List? ?? const [])
          .map((row) => KitchenPrinterSettings.fromJson(Map<String, dynamic>.from(row as Map)))
          .toList(),
      printState: rawState.map(
        (key, value) => MapEntry(
          key,
          KitchenPrintState.fromJson(Map<String, dynamic>.from(value as Map)),
        ),
      ),
    );
  }

  final List<KitchenPrinterSettings> counterSettings;
  final Map<String, KitchenPrintState> printState;
}

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
    this.printCount = 0,
    this.lastPrintedAt,
    this.lastPrintedBy,
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
      printCount: (json['print_count'] as num?)?.toInt() ?? 0,
      lastPrintedAt: DateTime.tryParse(json['last_printed_at']?.toString() ?? ''),
      lastPrintedBy: json['last_printed_by']?.toString(),
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
  final int printCount;
  final DateTime? lastPrintedAt;
  final String? lastPrintedBy;

  KitchenOrderItem withPrintState(KitchenPrintState? state) {
    if (state == null) return this;
    return KitchenOrderItem(
      rowName: rowName,
      itemCode: itemCode,
      itemName: itemName,
      qty: qty,
      uom: uom,
      kitchenCounter: kitchenCounter,
      preparationStatus: preparationStatus,
      kitchenNote: kitchenNote,
      createdAt: createdAt,
      printCount: state.printCount,
      lastPrintedAt: state.lastPrintedAt,
      lastPrintedBy: state.lastPrintedBy,
    );
  }

  String get displayPreparationStatus => preparationStatus == 'Accepted' ? 'Preparing' : preparationStatus;

  String? get nextAction => switch (preparationStatus) {
        'New' => 'Start Preparation',
        'Accepted' => 'Mark Ready',
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
  const KitchenOrdersResponse({
    required this.orders,
    required this.allowedCounters,
    required this.counterSettings,
  });

  factory KitchenOrdersResponse.fromJson(Map<String, dynamic> json) {
    return KitchenOrdersResponse(
      orders: (json['orders'] as List? ?? const [])
          .map((row) => KitchenOrder.fromJson(Map<String, dynamic>.from(row as Map)))
          .toList(),
      allowedCounters: (json['allowed_counters'] as List? ?? const [])
          .map((value) => value.toString())
          .toList(),
      counterSettings: (json['counter_settings'] as List? ?? const [])
          .map((row) => KitchenPrinterSettings.fromJson(Map<String, dynamic>.from(row as Map)))
          .toList(),
    );
  }

  final List<KitchenOrder> orders;
  final List<String> allowedCounters;
  final List<KitchenPrinterSettings> counterSettings;

  KitchenOrdersResponse withPrintSnapshot(KitchenPrintSnapshot snapshot) {
    return KitchenOrdersResponse(
      orders: orders
          .map(
            (order) => KitchenOrder(
              name: order.name,
              customer: order.customer,
              session: order.session,
              creation: order.creation,
              preparationSummary: order.preparationSummary,
              items: order.items
                  .map((item) => item.withPrintState(snapshot.printState[item.rowName]))
                  .toList(),
            ),
          )
          .toList(),
      allowedCounters: allowedCounters,
      counterSettings: snapshot.counterSettings,
    );
  }

  KitchenPrinterSettings? settingsForCounter(String counterName) {
    for (final settings in counterSettings) {
      if (settings.counterName == counterName) return settings;
    }
    return null;
  }
}
