class BootstrapPermissions {
  const BootstrapPermissions({
    required this.waiter,
    bool kitchen = false,
    required this.cashier,
    required this.manager,
    this.canRequestCashierPrint = false,
    this.canViewPrintStatus = false,
    this.canRetryPrintJobs = false,
  });

  factory BootstrapPermissions.fromJson(Map<String, dynamic> json) {
    return BootstrapPermissions(
      waiter: json['waiter'] == true,
      cashier: json['cashier'] == true,
      manager: json['manager'] == true,
      canRequestCashierPrint: json['can_request_cashier_print'] == true,
      canViewPrintStatus: json['can_view_print_status'] == true,
      canRetryPrintJobs: json['can_retry_print_jobs'] == true,
    );
  }

  final bool waiter;
  final bool cashier;
  final bool manager;
  final bool canRequestCashierPrint;
  final bool canViewPrintStatus;
  final bool canRetryPrintJobs;
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
      roles: (json['roles'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(),
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
