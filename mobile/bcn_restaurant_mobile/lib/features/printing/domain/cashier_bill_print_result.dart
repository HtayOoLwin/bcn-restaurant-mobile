class CashierBillPrintResult {
  const CashierBillPrintResult({
    required this.salesOrder,
    required this.requestId,
    required this.printJob,
    required this.status,
    required this.isReprint,
    required this.duplicate,
  });

  factory CashierBillPrintResult.fromJson(Map<String, dynamic> json) {
    final salesOrder = json['sales_order']?.toString().trim() ?? '';
    final requestId = json['request_id']?.toString().trim() ?? '';
    final printJob = json['print_job']?.toString().trim() ?? '';
    final status = json['status']?.toString().trim() ?? '';

    if (salesOrder.isEmpty) {
      throw const FormatException('Cashier print response has no sales_order.');
    }
    if (requestId.isEmpty) {
      throw const FormatException('Cashier print response has no request_id.');
    }
    if (printJob.isEmpty) {
      throw const FormatException('Cashier print response has no print_job.');
    }
    if (status.isEmpty) {
      throw const FormatException('Cashier print response has no status.');
    }

    return CashierBillPrintResult(
      salesOrder: salesOrder,
      requestId: requestId,
      printJob: printJob,
      status: status,
      isReprint: _asBool(json['is_reprint'], field: 'is_reprint'),
      duplicate: _asBool(json['duplicate'], field: 'duplicate'),
    );
  }

  final String salesOrder;
  final String requestId;
  final String printJob;
  final String status;
  final bool isReprint;
  final bool duplicate;
}

bool _asBool(Object? value, {required String field}) {
  // Older Server Scripts may omit these optional response metadata flags.
  if (value == null) return false;
  if (value is bool) return value;
  if (value == 1) return true;
  if (value == 0) return false;
  if (value is String) {
    switch (value.trim().toLowerCase()) {
      case 'true':
      case '1':
        return true;
      case 'false':
      case '0':
      case '':
        return false;
    }
  }
  throw FormatException('Cashier print response has an invalid $field value.');
}
