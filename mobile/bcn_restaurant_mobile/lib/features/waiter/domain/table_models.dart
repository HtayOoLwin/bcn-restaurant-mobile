class RestaurantTableModel {
  const RestaurantTableModel({
    required this.customer,
    required this.customerName,
    required this.customerGroup,
    required this.isOpen,
    this.session,
    this.sessionStatus,
    this.waiter,
    this.openedAt,
  });

  factory RestaurantTableModel.fromJson(Map<String, dynamic> json) {
    return RestaurantTableModel(
      customer: json['customer']?.toString() ?? '',
      customerName: json['customer_name']?.toString() ?? '',
      customerGroup: json['customer_group']?.toString() ?? '',
      isOpen: json['is_open'] == true,
      session: json['session']?.toString(),
      sessionStatus: json['session_status']?.toString(),
      waiter: json['waiter']?.toString(),
      openedAt: json['opened_at']?.toString(),
    );
  }

  final String customer;
  final String customerName;
  final String customerGroup;
  final bool isOpen;
  final String? session;
  final String? sessionStatus;
  final String? waiter;
  final String? openedAt;
}

class TablesResponse {
  const TablesResponse({
    required this.serviceType,
    required this.customerGroup,
    required this.customerGroups,
    required this.tables,
  });

  factory TablesResponse.fromJson(Map<String, dynamic> json) {
    return TablesResponse(
      serviceType: json['service_type']?.toString() ?? 'customer_group',
      customerGroup: json['customer_group']?.toString() ?? '',
      customerGroups: (json['customer_groups'] as List? ?? const [])
          .map((e) => e.toString())
          .where((name) => name.isNotEmpty)
          .toList(),
      tables: (json['tables'] as List? ?? const [])
          .map(
            (row) => RestaurantTableModel.fromJson(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList(),
    );
  }

  final String serviceType;
  final String customerGroup;
  final List<String> customerGroups;
  final List<RestaurantTableModel> tables;
}
