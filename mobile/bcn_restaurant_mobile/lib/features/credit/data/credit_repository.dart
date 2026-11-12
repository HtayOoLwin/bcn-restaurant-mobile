import '../../../core/network/api_client.dart';

class CreditRepository {
  const CreditRepository(this._api);
  final ApiClient _api;

  Future<List<CreditCustomer>> customers() async {
    final data = Map<String, dynamic>.from(
      await _api.getMethod('bcn_get_credit_customers') as Map,
    );
    return (data['customers'] as List? ?? const [])
        .map((row) => CreditCustomer.fromJson(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  Future<List<CreditInvoice>> invoices(String customer) async {
    final data = Map<String, dynamic>.from(
      await _api.getMethod(
        'bcn_get_customer_credit_details',
        queryParameters: {'customer': customer},
      ) as Map,
    );
    return (data['invoices'] as List? ?? const [])
        .map((row) => CreditInvoice.fromJson(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  Future<Map<String, dynamic>> receive({
    required String invoice,
    required double amount,
    required String modeOfPayment,
    required String requestId,
    String referenceNo = '',
  }) async {
    final data = await _api.postMethod('bcn_receive_credit_payment', data: {
      'invoice': invoice,
      'amount': amount,
      'mode_of_payment': modeOfPayment,
      'request_id': requestId,
      'reference_no': referenceNo,
    });
    return Map<String, dynamic>.from(data as Map);
  }
}

double _number(dynamic value) =>
    value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '') ?? 0;

class CreditCustomer {
  const CreditCustomer({
    required this.customer,
    required this.customerName,
    required this.currency,
    required this.outstanding,
    required this.invoiceCount,
  });
  factory CreditCustomer.fromJson(Map<String, dynamic> json) => CreditCustomer(
        customer: json['customer']?.toString() ?? '',
        customerName: json['customer_name']?.toString() ?? '',
        currency: json['currency']?.toString() ?? 'MMK',
        outstanding: _number(json['outstanding_amount']),
        invoiceCount: (json['invoice_count'] as num?)?.toInt() ?? 0,
      );
  final String customer;
  final String customerName;
  final String currency;
  final double outstanding;
  final int invoiceCount;
}

class CreditInvoice {
  const CreditInvoice({
    required this.name,
    required this.currency,
    required this.outstanding,
    required this.grandTotal,
    required this.postingDate,
    required this.dueDate,
  });
  factory CreditInvoice.fromJson(Map<String, dynamic> json) => CreditInvoice(
        name: json['invoice']?.toString() ?? '',
        currency: json['currency']?.toString() ?? 'MMK',
        outstanding: _number(json['outstanding_amount']),
        grandTotal: _number(json['grand_total']),
        postingDate: json['posting_date']?.toString() ?? '',
        dueDate: json['due_date']?.toString() ?? '',
      );
  final String name;
  final String currency;
  final double outstanding;
  final double grandTotal;
  final String postingDate;
  final String dueDate;
}
