class CashierPaymentTender {
  const CashierPaymentTender({required this.modeOfPayment, required this.amount});

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

class CashierPrinterSettings {
  const CashierPrinterSettings({
    required this.printerIp,
    required this.printerPort,
    required this.paperWidth,
  });

  factory CashierPrinterSettings.fromJson(Map<String, dynamic> json) {
    return CashierPrinterSettings(
      printerIp: json['printer_ip']?.toString().trim() ?? '',
      printerPort: _asInt(json['printer_port']) == 0 ? 9100 : _asInt(json['printer_port']),
      paperWidth: json['paper_width']?.toString() ?? '80mm',
    );
  }

  final String printerIp;
  final int printerPort;
  final String paperWidth;

  bool get isConfigured => printerIp.isNotEmpty && printerPort > 0;
}

class CashierInvoiceTax {
  const CashierInvoiceTax({
    required this.description,
    required this.rate,
    required this.taxAmount,
    required this.chargeType,
  });

  factory CashierInvoiceTax.fromJson(Map<String, dynamic> json) {
    return CashierInvoiceTax(
      description: json['description']?.toString() ?? json['account_head']?.toString() ?? 'Tax',
      rate: _asDouble(json['rate']),
      taxAmount: _asDouble(json['tax_amount']),
      chargeType: json['charge_type']?.toString() ?? '',
    );
  }

  final String description;
  final double rate;
  final double taxAmount;
  final String chargeType;
}

class CashierInvoiceItem {
  const CashierInvoiceItem({
    required this.itemCode,
    required this.itemName,
    required this.qty,
    required this.rate,
    required this.amount,
    required this.salesOrder,
    required this.warehouse,
    required this.kitchenCounter,
  });

  factory CashierInvoiceItem.fromJson(Map<String, dynamic> json) {
    return CashierInvoiceItem(
      itemCode: json['item_code']?.toString() ?? '',
      itemName: json['item_name']?.toString() ?? json['item_code']?.toString() ?? '',
      qty: _asDouble(json['qty']),
      rate: _asDouble(json['rate']),
      amount: _asDouble(json['amount']),
      salesOrder: json['sales_order']?.toString(),
      warehouse: json['warehouse']?.toString(),
      kitchenCounter: json['kitchen_counter']?.toString(),
    );
  }

  final String itemCode;
  final String itemName;
  final double qty;
  final double rate;
  final double amount;
  final String? salesOrder;
  final String? warehouse;
  final String? kitchenCounter;
}

class CashierInvoice {
  const CashierInvoice({
    required this.name,
    required this.customer,
    required this.customerName,
    required this.creation,
    required this.netTotal,
    required this.totalTaxesAndCharges,
    required this.grandTotal,
    required this.outstandingAmount,
    required this.currency,
    required this.docstatus,
    required this.paymentStatus,
    required this.salesOrders,
    required this.items,
    required this.taxes,
    required this.billPrinted,
    required this.billPrintedTotal,
    this.billPrintedAt,
    this.billPrintedBy,
  });

  factory CashierInvoice.fromJson(Map<String, dynamic> json) {
    return CashierInvoice(
      name: json['name']?.toString() ?? '',
      customer: json['customer']?.toString() ?? '',
      customerName: json['customer_name']?.toString() ?? json['customer']?.toString() ?? '',
      creation: json['creation']?.toString(),
      netTotal: _asDouble(json['net_total']),
      totalTaxesAndCharges: _asDouble(json['total_taxes_and_charges']),
      grandTotal: _asDouble(json['grand_total']),
      outstandingAmount: _asDouble(json['outstanding_amount']),
      currency: json['currency']?.toString() ?? '',
      docstatus: _asInt(json['docstatus']),
      paymentStatus: json['payment_status']?.toString() ?? '',
      salesOrders: (json['sales_orders'] as List? ?? const [])
          .map((value) => value.toString())
          .toList(),
      items: (json['items'] as List? ?? const [])
          .map((value) => CashierInvoiceItem.fromJson(Map<String, dynamic>.from(value as Map)))
          .toList(),
      taxes: (json['taxes'] as List? ?? const [])
          .map((value) => CashierInvoiceTax.fromJson(Map<String, dynamic>.from(value as Map)))
          .toList(),
      billPrinted: json['bill_printed'] == true || json['bill_printed'] == 1,
      billPrintedTotal: _asDouble(json['bill_printed_total']),
      billPrintedAt: DateTime.tryParse(json['bill_printed_at']?.toString() ?? ''),
      billPrintedBy: json['bill_printed_by']?.toString(),
    );
  }

  final String name;
  final String customer;
  final String customerName;
  final String? creation;
  final double netTotal;
  final double totalTaxesAndCharges;
  final double grandTotal;
  final double outstandingAmount;
  final String currency;
  final int docstatus;
  final String paymentStatus;
  final List<String> salesOrders;
  final List<CashierInvoiceItem> items;
  final List<CashierInvoiceTax> taxes;
  final bool billPrinted;
  final double billPrintedTotal;
  final DateTime? billPrintedAt;
  final String? billPrintedBy;
}

class CashierBillingResponse {
  const CashierBillingResponse({
    required this.invoices,
    required this.modes,
    required this.printerSettings,
    this.paymentEntry,
    this.paymentEntries = const [],
    this.changeAmount = 0,
  });

  factory CashierBillingResponse.fromJson(Map<String, dynamic> json) {
    return CashierBillingResponse(
      invoices: (json['invoices'] as List? ?? const [])
          .map((value) => CashierInvoice.fromJson(Map<String, dynamic>.from(value as Map)))
          .toList(),
      modes: (json['modes'] as List? ?? const [])
          .map((value) => CashierPaymentMode.fromJson(Map<String, dynamic>.from(value as Map)))
          .where((mode) => mode.name.isNotEmpty)
          .toList(),
      printerSettings: CashierPrinterSettings.fromJson(
        Map<String, dynamic>.from(json['printer_settings'] as Map? ?? const {}),
      ),
      paymentEntry: json['payment_entry']?.toString(),
      paymentEntries: (json['payment_entries'] as List? ?? const [])
          .map((value) => value.toString())
          .where((value) => value.isNotEmpty)
          .toList(),
      changeAmount: _asDouble(json['change_amount']),
    );
  }

  final List<CashierInvoice> invoices;
  final List<CashierPaymentMode> modes;
  final CashierPrinterSettings printerSettings;
  final String? paymentEntry;
  final List<String> paymentEntries;
  final double changeAmount;
}

double _asDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
