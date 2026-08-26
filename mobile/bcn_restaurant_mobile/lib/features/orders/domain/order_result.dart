class OrderResult {
  const OrderResult({
    required this.salesOrder,
    required this.session,
    required this.grandTotal,
    required this.preparationSummary,
    required this.duplicate,
  });

  factory OrderResult.fromJson(Map<String, dynamic> json) {
    return OrderResult(
      salesOrder: json['sales_order']?.toString() ?? '',
      session: json['session']?.toString() ?? '',
      grandTotal: (json['grand_total'] as num?)?.toDouble() ?? 0,
      preparationSummary: json['preparation_summary']?.toString() ?? 'New',
      duplicate: json['duplicate'] == true,
    );
  }

  final String salesOrder;
  final String session;
  final double grandTotal;
  final String preparationSummary;
  final bool duplicate;
}
