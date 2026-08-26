class BootstrapPermissions {
  const BootstrapPermissions({
    required this.waiter,
    required this.kitchen,
    required this.cashier,
    required this.manager,
  });

  factory BootstrapPermissions.fromJson(Map<String, dynamic> json) {
    return BootstrapPermissions(
      waiter: json['waiter'] == true,
      kitchen: json['kitchen'] == true,
      cashier: json['cashier'] == true,
      manager: json['manager'] == true,
    );
  }

  final bool waiter;
  final bool kitchen;
  final bool cashier;
  final bool manager;
}

class BootstrapModel {
  const BootstrapModel({
    required this.user,
    required this.fullName,
    required this.roles,
    required this.permissions,
    required this.company,
    required this.currency,
    required this.sellingPriceList,
    required this.kitchenCounters,
  });

  factory BootstrapModel.fromJson(Map<String, dynamic> json) {
    return BootstrapModel(
      user: json['user']?.toString() ?? '',
      fullName: json['full_name']?.toString() ?? '',
      roles: (json['roles'] as List? ?? const []).map((e) => e.toString()).toList(),
      permissions: BootstrapPermissions.fromJson(
        Map<String, dynamic>.from(json['permissions'] as Map? ?? const {}),
      ),
      company: json['company']?.toString() ?? '',
      currency: json['currency']?.toString() ?? '',
      sellingPriceList: json['selling_price_list']?.toString() ?? '',
      kitchenCounters: (json['kitchen_counters'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(),
    );
  }

  final String user;
  final String fullName;
  final List<String> roles;
  final BootstrapPermissions permissions;
  final String company;
  final String currency;
  final String sellingPriceList;
  final List<String> kitchenCounters;
}
