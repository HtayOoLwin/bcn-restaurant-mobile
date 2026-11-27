import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../printing/data/android_print_repository.dart';
import '../../printing/domain/cashier_bill_print_result.dart';

import '../../../core/formatters/amount_format.dart';
import '../data/cashier_repository.dart';

class CashierDailyReportScreen extends ConsumerStatefulWidget {
  const CashierDailyReportScreen({super.key, required this.repository});

  final CashierRepository repository;

  @override
  ConsumerState<CashierDailyReportScreen> createState() => _CashierDailyReportScreenState();
}

class _CashierDailyReportScreenState extends ConsumerState<CashierDailyReportScreen> {
  DateTime _selectedDate = DateTime.now();
  String _invoiceSearch = '';
  late Future<Map<String, dynamic>> _report;
  final Set<String> _printingInvoices = {};
  final Map<String, String> _unconfirmedRequestIds = {};

  String _newPrintRequestId() {
    final nonce = Random.secure().nextInt(0x7fffffff).toRadixString(16);
    return 'daily-reprint-${DateTime.now().microsecondsSinceEpoch}-$nonce';
  }

  Future<void> _reprintReceipt({
    required String invoiceName,
    required String salesOrder,
  }) async {
    if (!mounted || _printingInvoices.contains(invoiceName)) return;
    setState(() => _printingInvoices.add(invoiceName));
    final requestId = _unconfirmedRequestIds[invoiceName] ?? _newPrintRequestId();

    try {
      final result = await ref.read(androidPrintRepositoryProvider).requestCashierBill(
        salesOrder: salesOrder,
        requestId: requestId,
        printSource: 'daily_report',
      );
      if (!mounted) return;
      if (result.status.trim().toLowerCase() == 'failed') {
        _unconfirmedRequestIds.remove(invoiceName);
        throw StateError(
          'Print Job ${result.printJob} is Failed. Check the Android '
          'Printer Worker and use Reprint Receipt to create a new job.',
        );
      }
      setState(() => _unconfirmedRequestIds.remove(invoiceName));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.duplicate
                ? 'Existing print job: ${result.printJob} (${result.status})'
                : 'Receipt print job queued: ${result.printJob} (${result.status})',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      // Preserve the request ID after an ambiguous transport failure.
      // The retry will discover an already-created job instead of
      // generating a duplicate physical receipt.
      if (error is CashierPrintServerException) {
        _unconfirmedRequestIds.remove(invoiceName);
      } else {
        _unconfirmedRequestIds.putIfAbsent(invoiceName, () => requestId);
      }
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Receipt reprint failed'),
          content: SelectableText(
            'Sales Invoice: $invoiceName\n'
            'Sales Order: $salesOrder\n\n$error\n\n'
            'Payment has not been repeated. Check the printer before retrying.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _printingInvoices.remove(invoiceName));
    }
  }

  String _dateText(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  String _displayDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _report = widget.repository.getDailyReport(_dateText(_selectedDate));
  }

  Future<void> _chooseDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _selectedDate = selected;
      _load();
    });
  }

  Widget _metric(String title, num amount, String currency,
      Color bg, Color fg, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(icon, color: fg, size: 20),
          const SizedBox(width: 6),
          Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600))),
        ]),
        const SizedBox(height: 9),
        Text(formatAmount(amount), textAlign: TextAlign.right,
          style: TextStyle(color: fg, fontWeight: FontWeight.bold, fontSize: 19)),
      ]),
    );
  }

  Widget _line(String label, num amount, String currency) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(children: [
      Expanded(child: Text(label)),
      Text(formatMoney(amount, currency),
          textAlign: TextAlign.right,
          style: const TextStyle(fontWeight: FontWeight.w600)),
    ]),
  );

  @override
  Widget build(BuildContext context) {
    final desktop = Theme.of(context).platform == TargetPlatform.windows && MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily Sales Report'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => setState(_load),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          if (desktop)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                          SizedBox(
                            width: 170,
                            child: Semantics(
                              button: true,
                              label: 'Report date',
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: _chooseDate,
                                child: InputDecorator(
                                  decoration: const InputDecoration(
                                    labelText: 'Report Date',
                                    isDense: true,
                                    contentPadding: EdgeInsets.all(10),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.calendar_today_outlined, size: 18, color: Color(0xFF315F8E)),
                                      const SizedBox(width: 8),
                                      Expanded(child: Text(_displayDate(_selectedDate), maxLines: 1, overflow: TextOverflow.ellipsis)),
                                      const Icon(Icons.arrow_drop_down),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                  const SizedBox(width: 8),
                  TextButton(onPressed: () => setState(() {
                    _selectedDate = DateTime.now();
                    _load();
                  }), child: const Text('Today')),
                  const Spacer(),
                  OutlinedButton.icon(onPressed: () => setState(_load),
                    icon: const Icon(Icons.refresh, size: 18), label: const Text('Refresh')),
                ],
              ),
            )
          else Container(
            margin: const EdgeInsets.all(10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF205F91),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const SizedBox(height: 12),
              Material(color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(onTap: _chooseDate,
                  child: Padding(padding: const EdgeInsets.all(13),
                    child: Row(children: [
                      const Icon(Icons.calendar_today_outlined),
                      const SizedBox(width: 10),
                      Expanded(child: Text(_displayDate(_selectedDate))),
                      const Icon(Icons.keyboard_arrow_down),
                    ]))),
              ),
            ]),
          ),
          Expanded(
            child: FutureBuilder<Map<String, dynamic>>(
              future: _report,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Could not load daily report: ${snapshot.error}'),
                  ));
                }
                final data = snapshot.data ?? const <String, dynamic>{};
                final currency = data['currency']?.toString() ?? 'MMK';
                num amount(String key) => (data[key] as num?) ?? 0;
                final invoices = (data['invoices'] as List? ?? const []);
                final visibleInvoices = desktop
                    ? invoices.where((raw) {
                        if (raw is! Map) return false;
                        final query = _invoiceSearch.trim().toLowerCase();
                        return ['name', 'customer', 'sales_order'].any(
                          (key) => (raw[key]?.toString() ?? '').toLowerCase().contains(query),
                        );
                      }).toList()
                    : invoices;
                return Column(children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [

                    LayoutBuilder(builder: (context, constraints) {
                      final columns = desktop && constraints.maxWidth >= 720 ? 4 : 2;
                      final width = (constraints.maxWidth - 10 * (columns - 1)) / columns;
                      return Wrap(spacing: 10, runSpacing: 10, children: [
                        SizedBox(width: width, child: _metric(
                          'Total Sales', amount('total_sales'), currency,
                          const Color(0xFFD8EDFF), const Color(0xFF155B98),
                          Icons.bar_chart)),
                        SizedBox(width: width, child: _metric(
                          'Paid Amount', amount('total_paid'), currency,
                          const Color(0xFFDDF3E6), const Color(0xFF14683E),
                          Icons.account_balance_wallet_outlined)),
                        SizedBox(width: width, child: _metric(
                          'Outstanding', amount('total_outstanding'), currency,
                          const Color(0xFFFCE7E8), const Color(0xFFAC262C),
                          Icons.error_outline)),
                        SizedBox(width: width, child: _metric(
                          'Invoices', (data['invoice_count'] as num?) ?? 0, currency,
                          const Color(0xFFEAE3FA), const Color(0xFF61499B),
                          Icons.description_outlined)),
                      ]);
                    }),
                    const SizedBox(height: 12),
                    Card(
                      color: desktop ? Colors.white : const Color(0xFFDDEBFA),
                      surfaceTintColor: Colors.transparent,
                      child: Padding(
                      padding: EdgeInsets.all(desktop ? 10 : 14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text('Payment Method Summary',
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                          if ((data['payment_method_summary'] as List? ?? const []).isEmpty)
                            const Padding(padding: EdgeInsets.only(top: 8),
                              child: Text('No linked payment entries found for these invoices.',
                                style: TextStyle(fontSize: 12, color: Colors.grey))),
                          for (final raw in (data['payment_method_summary'] as List? ?? const []))
                            if (raw is Map)
                              _line(raw['name']?.toString() ?? 'Other',
                                (raw['amount'] as num?) ?? 0, currency),
                        ]),
                    )),
                    const SizedBox(height: 12),
                    ]),
                  ),
                  Expanded(child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                    children: [
                    if (desktop)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(children: [
                          Expanded(child: Text('Sales Invoices (${visibleInvoices.length})',
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold))),
                          SizedBox(width: 250, child: TextField(
                            decoration: const InputDecoration(
                              hintText: 'Search invoice or customer',
                              prefixIcon: Icon(Icons.search, size: 18),
                              isDense: true,
                            ),
                            onChanged: (value) => setState(() => _invoiceSearch = value),
                          )),
                        ]),
                      )
                    else const Text('Sales Invoice List',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                    if (desktop && invoices.isNotEmpty && visibleInvoices.isEmpty)
                      const Padding(padding: EdgeInsets.all(20), child: Text('No matching invoices.')),
                    if (desktop && visibleInvoices.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(color: const Color(0xFFE3EFFC), borderRadius: BorderRadius.circular(8)),
                        child: const Row(children: [
                          SizedBox(width: 32),
                          Expanded(flex: 3, child: Text('Invoice No.', style: TextStyle(fontWeight: FontWeight.w700))),
                          Expanded(flex: 2, child: Text('Customer', style: TextStyle(fontWeight: FontWeight.w700))),
                          Expanded(flex: 2, child: Text('Status', style: TextStyle(fontWeight: FontWeight.w700))),
                          Expanded(flex: 2, child: Text('Amount', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w700))),
                          SizedBox(width: 48),
                        ]),
                      ),
                    if (invoices.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('No submitted Sales Invoices for this date.'),
                      ),
                    for (final raw in visibleInvoices)
                      if (raw is Map)
                        Builder(builder: (context) {
                          final grand = (raw['grand_total'] as num?) ?? 0;
                          final due = (raw['outstanding'] as num?) ?? 0;
                          final methods = raw['payment_methods'] as List? ?? const [];
                          final fullCredit = due > 0.01 && (grand - due).abs() < 0.01;
                          final partialCredit = due > 0.01 && !fullCredit;
                          final status = fullCredit ? 'Full Credit' :
                              partialCredit ? 'Partial Credit' :
                              methods.length > 1 ? 'Split' :
                              methods.isNotEmpty && methods.first is Map
                                ? (methods.first as Map)['name']?.toString() ?? 'Paid'
                                : 'Paid';
                          final statusColor = due > 0.01
                              ? const Color(0xFFB6292F)
                              : const Color(0xFF14683E);
                          return Card(
                            color: Colors.white,
                            child: ExpansionTile(
                              leading: const Icon(Icons.receipt_long, color: Color(0xFF205F91)),
                              dense: desktop,
                              title: desktop ? Row(children: [
                                Expanded(flex: 3, child: Text(raw['name']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
                                Expanded(flex: 2, child: Text(raw['customer']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis)),
                                Expanded(flex: 2, child: Text(status, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: statusColor))),
                                Expanded(flex: 2, child: Text(formatMoney(grand, currency), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700))),
                              ]) : Row(children: [
                                Expanded(child: Text(raw['name']?.toString() ?? '',
                                    maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.bold))),
                                Text(status, style: TextStyle(fontSize: 11,
                                    fontWeight: FontWeight.bold, color: statusColor)),
                              ]),
                              subtitle: desktop ? null : Row(children: [
                                Expanded(child: Text(raw['customer']?.toString() ?? '',
                                    maxLines: 1, overflow: TextOverflow.ellipsis)),
                                Text(formatMoney(grand, currency),
                                    style: const TextStyle(fontWeight: FontWeight.bold)),
                              ]),
                              childrenPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              children: [
                                if (!fullCredit)
                                  for (final method in methods)
                                    if (method is Map)
                                      _line(method['name']?.toString() ?? 'Other',
                                        (method['amount'] as num?) ?? 0, currency),
                                if (due > 0.01)
                                  _line('Outstanding', due, currency),
                                const SizedBox(height: 10),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: Builder(
                                    builder: (context) {
                                      final invoiceName =
                                          raw['name']?.toString().trim() ?? '';
                                      final salesOrder =
                                          raw['sales_order']?.toString().trim() ?? '';
                                      final busy = _printingInvoices.contains(invoiceName);
                                      return FilledButton.icon(
                                        onPressed: invoiceName.isEmpty ||
                                                salesOrder.isEmpty ||
                                                busy
                                            ? null
                                            : () => _reprintReceipt(
                                                  invoiceName: invoiceName,
                                                  salesOrder: salesOrder,
                                                ),
                                        icon: busy
                                            ? const SizedBox(
                                                width: 16,
                                                height: 16,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                ),
                                              )
                                            : const Icon(Icons.print),
                                        label: Text(busy ? 'Sending…' : 'Reprint Receipt'),
                                      );
                                    },
                                  ),
                                ),
                                if ((raw['sales_order']?.toString().trim() ?? '').isEmpty)
                                  const Padding(
                                    padding: EdgeInsets.only(top: 6),
                                    child: Text(
                                      'Linked Sales Order is unavailable. Reprint disabled.',
                                      style: TextStyle(color: Colors.redAccent, fontSize: 12),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        }),
                    ],
                  )),
                ]);
              },
            ),
          ),
        ],
      ),
    );
  }
}
