class CashierPaymentTender {
  const CashierPaymentTender({
    required this.modeOfPayment,
    required this.amount,
  });

  final String modeOfPayment;
  final double amount;
}

class CashierPaymentMode {
  const CashierPaymentMode({required this.name, required this.isDefault});

  factory CashierPaymentMode.fromJson(Map<String, dynamic> json) {
    return CashierPaymentMode(
      name: json['name']?.toString() ?? '',
      isDefault: json['default'] == true || json['default'] == 1,
    );
  }

  final String name;
  final bool isDefault;
}

class CashierBillItem {
  const CashierBillItem({
    required this.itemCode,
    required this.itemName,
    required this.description,
    required this.qty,
    required this.uom,
    required this.rate,
    required this.amount,
    required this.netAmount,
  });

  factory CashierBillItem.fromJson(Map<String, dynamic> json) {
    return CashierBillItem(
      itemCode: json['item_code']?.toString() ?? '',
      itemName:
          json['item_name']?.toString() ?? json['item_code']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      qty: _asDouble(json['qty']),
      uom: json['uom']?.toString() ?? '',
      rate: _asDouble(json['rate']),
      amount: _asDouble(json['amount']),
      netAmount: _asDouble(json['net_amount']),
    );
  }

  final String itemCode;
  final String itemName;
  final String description;
  final double qty;
  final String uom;
  final double rate;
  final double amount;
  final double netAmount;
}

class CashierBillTax {
  const CashierBillTax({
    required this.chargeType,
    required this.accountHead,
    required this.description,
    required this.rate,
    required this.taxAmount,
    required this.total,
  });

  factory CashierBillTax.fromJson(Map<String, dynamic> json) {
    return CashierBillTax(
      chargeType: json['charge_type']?.toString() ?? '',
      accountHead: json['account_head']?.toString() ?? '',
      description:
          json['description']?.toString() ??
          json['account_head']?.toString() ??
          'Tax',
      rate: _asDouble(json['rate']),
      taxAmount: _asDouble(json['tax_amount']),
      total: _asDouble(json['total']),
    );
  }

  final String chargeType;
  final String accountHead;
  final String description;
  final double rate;
  final double taxAmount;
  final double total;
}

class CashierBill {
  const CashierBill({
    required this.salesOrder,
    required this.customer,
    required this.customerName,
    required this.creation,
    required this.netTotal,
    required this.totalTaxesAndCharges,
    required this.grandTotal,
    required this.currency,
    required this.restaurantStatus,
    required this.lastPrintStatus,
    required this.lastPrintJob,
    required this.items,
    required this.taxes,
  });

  factory CashierBill.fromJson(Map<String, dynamic> json) {
    return CashierBill(
      salesOrder: json['sales_order']?.toString() ?? '',
      customer: json['customer']?.toString() ?? '',
      customerName:
          json['customer_name']?.toString() ??
          json['customer']?.toString() ??
          '',
      creation: json['creation']?.toString(),
      netTotal: _asDouble(json['net_total']),
      totalTaxesAndCharges: _asDouble(json['total_taxes_and_charges']),
      grandTotal: _asDouble(json['grand_total']),
      currency: json['currency']?.toString() ?? '',
      restaurantStatus: json['restaurant_status']?.toString() ?? '',
      lastPrintStatus: json['last_print_status']?.toString(),
      lastPrintJob: json['last_print_job']?.toString(),
      items: (json['items'] as List? ?? const [])
          .map(
            (value) => CashierBillItem.fromJson(
              Map<String, dynamic>.from(value as Map),
            ),
          )
          .toList(),
      taxes: (json['taxes'] as List? ?? const [])
          .map(
            (value) => CashierBillTax.fromJson(
              Map<String, dynamic>.from(value as Map),
            ),
          )
          .toList(),
    );
  }

  final String salesOrder;
  final String customer;
  final String customerName;
  final String? creation;
  final double netTotal;
  final double totalTaxesAndCharges;
  final double grandTotal;
  final String currency;
  final String restaurantStatus;
  final String? lastPrintStatus;
  final String? lastPrintJob;
  final List<CashierBillItem> items;
  final List<CashierBillTax> taxes;
}

class CashierBillingResponse {
  const CashierBillingResponse({required this.bills, required this.modes});

  factory CashierBillingResponse.fromJson(Map<String, dynamic> json) {
    return CashierBillingResponse(
      bills: (json['bills'] as List? ?? const [])
          .map(
            (value) => CashierBill.fromJson(
              Map<String, dynamic>.from(value as Map),
            ),
          )
          .toList(),
      modes: (json['modes'] as List? ?? const [])
          .map(
            (value) => CashierPaymentMode.fromJson(
              Map<String, dynamic>.from(value as Map),
            ),
          )
          .where((mode) => mode.name.isNotEmpty)
          .toList(),
    );
  }

  final List<CashierBill> bills;
  final List<CashierPaymentMode> modes;
}

class CashierPaymentResult {
  const CashierPaymentResult({
    required this.salesOrder,
    required this.salesInvoice,
    required this.paymentEntries,
    required this.changeAmount,
    required this.duplicate,
  });

  factory CashierPaymentResult.fromJson(Map<String, dynamic> json) {
    return CashierPaymentResult(
      salesOrder: json['sales_order']?.toString() ?? '',
      salesInvoice: json['sales_invoice']?.toString() ?? '',
      paymentEntries: (json['payment_entries'] as List? ?? const [])
          .map((value) => value.toString())
          .where((value) => value.isNotEmpty)
          .toList(),
      changeAmount: _asDouble(json['change_amount']),
      duplicate: json['duplicate'] == true || json['duplicate'] == 1,
    );
  }

  final String salesOrder;
  final String salesInvoice;
  final List<String> paymentEntries;
  final double changeAmount;
  final bool duplicate;
}

double _asDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}
