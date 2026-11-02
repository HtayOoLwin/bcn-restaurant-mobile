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

  Widget _metric(String title, num amount, String currency) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 13)),
        const SizedBox(height: 5),
        Text(
          formatMoney(amount, currency),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ],
    );
  }

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
          Padding(
            padding: const EdgeInsets.all(12),
            child: OutlinedButton.icon(
              onPressed: _chooseDate,
              icon: const Icon(Icons.calendar_month),
              label: Text('Date: ${_dateText(_selectedDate)}'),
            ),
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
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Submitted Invoices: ${data['invoice_count'] ?? 0}',
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 14),
                            _metric('Total Sales', amount('total_sales'), currency),
                            const Divider(height: 24),
                            _metric('Paid', amount('total_paid'), currency),
                            const Divider(height: 24),
                            _metric('Outstanding', amount('total_outstanding'), currency),
                          ],
                        ),
                      ),
                    ),
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
