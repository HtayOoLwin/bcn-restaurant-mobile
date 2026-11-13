import 'package:flutter/material.dart';

import '../../../core/formatters/amount_format.dart';
import '../data/cashier_repository.dart';

class CashierSalesSummaryScreen extends StatefulWidget {
  const CashierSalesSummaryScreen({super.key, required this.repository});
  final CashierRepository repository;

  @override
  State<CashierSalesSummaryScreen> createState() => _CashierSalesSummaryScreenState();
}

class _CashierSalesSummaryScreenState extends State<CashierSalesSummaryScreen> {
  DateTime _from = DateTime.now();
  DateTime _to = DateTime.now();
  String _option = 'All';
  String _counter = '';
  String _search = '';
  late Future<Map<String, dynamic>> _report;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _display(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  double _num(dynamic n) =>
      n is num ? n.toDouble() : double.tryParse(n.toString()) ?? 0;

  void _load() {
    _report = widget.repository.getSalesSummaryByItem(
      fromDate: _iso(_from),
      toDate: _iso(_to),
      options: _option,
      salesCounter: _counter,
    );
  }

  Future<void> _pick(bool start) async {
    final chosen = await showDatePicker(
      context: context,
      initialDate: start ? _from : _to,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (chosen == null || !mounted) return;
    setState(() {
      if (start) {
        _from = chosen;
        if (_from.isAfter(_to)) _to = chosen;
      } else {
        _to = chosen;
        if (_to.isBefore(_from)) _from = chosen;
      }
      _load();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Sales Summary by Item'),
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: () => setState(_load),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Expanded(child: OutlinedButton.icon(
            onPressed: () => _pick(true),
            icon: const Icon(Icons.calendar_month),
            label: Text('From: ${_display(_from)}'),
          )),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton.icon(
            onPressed: () => _pick(false),
            icon: const Icon(Icons.calendar_month),
            label: Text('To: ${_display(_to)}'),
          )),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: DropdownButtonFormField<String>(
          initialValue: _option,
          decoration: const InputDecoration(
            labelText: 'Options', border: OutlineInputBorder()),
          items: const [
            DropdownMenuItem(value: 'All', child: Text('All')),
            DropdownMenuItem(value: 'Sales', child: Text('Sales')),
            DropdownMenuItem(value: 'Return', child: Text('Return')),
          ],
          onChanged: (value) {
            if (value == null) return;
            setState(() { _option = value; _load(); });
          },
        ),
      ),
      const SizedBox(height: 8),
      Expanded(child: FutureBuilder<Map<String, dynamic>>(
        future: _report,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Padding(
              padding: const EdgeInsets.all(18),
              child: Text('Unable to load Sales Summary: ${snapshot.error}'),
            ));
          }
          final data = snapshot.data ?? <String, dynamic>{};
          final currency = data['currency']?.toString() ?? 'MMK';
          final counters = (data['counters'] as List? ?? const [])
              .map((e) => e.toString()).where((e) => e.isNotEmpty).toSet().toList()..sort();
          final rows = (data['rows'] as List? ?? const [])
              .whereType<Map>().map((r) => Map<String, dynamic>.from(r))
              .where((r) {
                final q = _search.trim().toLowerCase();
                return q.isEmpty ||
                    (r['item_name'] ?? '').toString().toLowerCase().contains(q) ||
                    (r['item_code'] ?? '').toString().toLowerCase().contains(q);
              }).toList();
          final qty = rows.fold<double>(0, (s, r) => s + _num(r['qty']));
          final foc = rows.fold<double>(0, (s, r) => s + _num(r['foc_qty']));
          final total = rows.fold<double>(0, (s, r) => s + _num(r['amount']));
          return ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 24), children: [
            DropdownButtonFormField<String>(
              key: ValueKey(_counter),
              initialValue: counters.contains(_counter) ? _counter : '',
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Sales Counter', border: OutlineInputBorder()),
              items: [
                const DropdownMenuItem(value: '', child: Text('All Counters')),
                for (final name in counters)
                  DropdownMenuItem(value: name, child: Text(name,
                    overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() { _counter = value; _load(); });
              },
            ),
            const SizedBox(height: 8),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Search Item', prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder()),
              onChanged: (value) => setState(() => _search = value),
            ),
            const SizedBox(height: 10),
            Card(child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('Total Qty (includes FOC)'),
                  Text(formatAmount(qty),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                ]),
                if (foc != 0)
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text('FOC Qty'), Text(formatAmount(foc)),
                  ]),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('Total Amount'),
                  Text(formatMoney(total, currency),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                ]),
              ]),
            )),
            if (data['foc_detection_available'] != true)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'FOC mapping is not configured or not detected in ERPNext. '
                  'Verify the Sales Order/Sales Invoice FOC flag before relying on FOC Qty.',
                  style: TextStyle(color: Colors.deepOrange, fontSize: 12),
                ),
              ),
            if (rows.isEmpty)
              const Padding(padding: EdgeInsets.all(20),
                child: Center(child: Text('No sales items for these filters.'))),
            for (final row in rows)
              Card(child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(row['item_name']?.toString() ?? '',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('Qty: ${formatAmount(_num(row['qty']))}'),
                    Text(formatMoney(_num(row['amount']), currency),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  ]),
                  if (_num(row['foc_qty']) != 0)
                    Padding(padding: const EdgeInsets.only(top: 4),
                      child: Text('FOC Qty: ${formatAmount(_num(row['foc_qty']))}',
                        style: const TextStyle(color: Colors.deepOrange, fontSize: 12))),
                ]),
              )),
            const SizedBox(height: 8),
            const Text('Qty includes FOC Qty; do not add FOC Qty again.',
              style: TextStyle(fontSize: 12, color: Colors.black54)),
          ]);
        },
      )),
    ]),
  );
}
