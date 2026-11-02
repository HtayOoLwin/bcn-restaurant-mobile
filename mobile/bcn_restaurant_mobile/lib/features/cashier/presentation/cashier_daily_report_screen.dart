import 'package:flutter/material.dart';

import '../../../core/formatters/amount_format.dart';
import '../data/cashier_repository.dart';

class CashierDailyReportScreen extends StatefulWidget {
  const CashierDailyReportScreen({super.key, required this.repository});

  final CashierRepository repository;

  @override
  State<CashierDailyReportScreen> createState() => _CashierDailyReportScreenState();
}

class _CashierDailyReportScreenState extends State<CashierDailyReportScreen> {
  DateTime _selectedDate = DateTime.now();
  late Future<Map<String, dynamic>> _report;

  String _dateText(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

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
      child: Row(children: [
        Icon(icon, color: fg, size: 20),
        const SizedBox(width: 6),
        Expanded(child: Text(title, style: TextStyle(color: fg, fontSize: 12))),
        Flexible(child: Text(formatAmount(amount), textAlign: TextAlign.right,
          style: TextStyle(color: fg, fontWeight: FontWeight.bold, fontSize: 16))),
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
          Container(
            margin: const EdgeInsets.all(10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF205F91),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Row(children: [
                Expanded(child: Text('Daily Sales Report',
                  style: TextStyle(color: Colors.white, fontSize: 19,
                    fontWeight: FontWeight.bold))),
                Icon(Icons.calendar_month, color: Colors.white),
              ]),
              const SizedBox(height: 12),
              Material(color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(onTap: _chooseDate,
                  child: Padding(padding: const EdgeInsets.all(13),
                    child: Row(children: [
                      const Icon(Icons.calendar_today_outlined),
                      const SizedBox(width: 10),
                      Expanded(child: Text(_dateText(_selectedDate))),
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
                return ListView(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                  children: [
                    LayoutBuilder(builder: (context, constraints) {
                      final width = (constraints.maxWidth - 10) / 2;
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
                    Card(child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text('Payment Method Summary',
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                          for (final raw in (data['payment_method_summary'] as List? ?? const []))
                            if (raw is Map)
                              _line(raw['name']?.toString() ?? 'Other',
                                (raw['amount'] as num?) ?? 0, currency),
                        ]),
                    )),
                    const SizedBox(height: 12),
                    const Text('Sales Invoice List',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                    if (invoices.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('No submitted Sales Invoices for this date.'),
                      ),
                    for (final raw in invoices)
                      if (raw is Map)
                        Card(
                          child: ListTile(
                            title: Text(raw['name']?.toString() ?? ''),
                            subtitle: Text(raw['customer']?.toString() ?? ''),
                            trailing: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(formatMoney((raw['grand_total'] as num?) ?? 0, currency),
                                    style: const TextStyle(fontWeight: FontWeight.bold)),
                                if (((raw['outstanding'] as num?) ?? 0) != 0)
                                  Text('Due: ${formatMoney((raw['outstanding'] as num?) ?? 0, currency)}',
                                      style: const TextStyle(fontSize: 12)),
                              ],
                            ),
                          ),
                        ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
