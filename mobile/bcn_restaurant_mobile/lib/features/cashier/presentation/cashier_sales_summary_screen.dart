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
  DateTime _selectedDate = DateTime.now();
  String _counter = '';
  String _itemGroup = '';
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
      date: _iso(_selectedDate),
      salesCounter: _counter,
      itemGroup: _itemGroup,
    );
  }

  Future<void> _pickDate() async {
    final chosen = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (chosen == null || !mounted) return;
    setState(() {
      _selectedDate = chosen;
      _counter = '';
      _itemGroup = '';
      _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final desktop = Theme.of(context).platform == TargetPlatform.windows && MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
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
      if (!desktop) Card(
        margin: const EdgeInsets.all(12),
        color: const Color(0xFF205F91),
        child: InkWell(
          onTap: _pickDate,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              const Icon(Icons.calendar_month, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(child: Text(_display(_selectedDate),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ))),
              const Icon(Icons.arrow_drop_down, color: Colors.white),
            ]),
          ),
        ),
      ),
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
          final counters = (data['counters'] as List? ?? const [])
              .map((e) => e.toString()).where((e) => e.isNotEmpty).toSet().toList()..sort();
          final groups = (data['item_groups'] as List? ?? const [])
              .map((e) => e.toString()).where((e) => e.isNotEmpty)
              .toSet().toList()..sort();
          final rows = (data['rows'] as List? ?? const [])
              .whereType<Map>().map((r) => Map<String, dynamic>.from(r))
              .where((r) {
                final q = _search.trim().toLowerCase();
                return q.isEmpty ||
                    (r['item_name'] ?? '').toString().toLowerCase().contains(q) ||
                    (r['item_code'] ?? '').toString().toLowerCase().contains(q);
              }).toList();
          final qty = rows.fold<double>(0, (s, r) => s + _num(r['qty']));
          final total = rows.fold<double>(0, (s, r) => s + _num(r['amount']));
          if (desktop) {
            return Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    color: Colors.white,
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Wrap(
                        spacing: 10, runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SizedBox(
                            width: 170,
                            child: Semantics(
                              button: true,
                              label: 'Report date',
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: _pickDate,
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
                                      Expanded(child: Text(_display(_selectedDate), maxLines: 1, overflow: TextOverflow.ellipsis)),
                                      const Icon(Icons.arrow_drop_down),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: 170, child: DropdownButtonFormField<String>(
                            key: ValueKey('desktop-counter-$_counter'),
                            initialValue: counters.contains(_counter) ? _counter : '',
                            isExpanded: true,
                            decoration: const InputDecoration(labelText: 'Counter', isDense: true, contentPadding: EdgeInsets.all(10)),
                            items: [const DropdownMenuItem(value: '', child: Text('All Counters')),
                              for (final name in counters) DropdownMenuItem(value: name, child: Text(name, overflow: TextOverflow.ellipsis))],
                            onChanged: (value) { if (value == null) return; setState(() { _counter = value; _itemGroup = ''; _load(); }); },
                          )),
                          SizedBox(width: 180, child: DropdownButtonFormField<String>(
                            key: ValueKey('desktop-group-$_counter-$_itemGroup'),
                            initialValue: groups.contains(_itemGroup) ? _itemGroup : '',
                            isExpanded: true,
                            decoration: const InputDecoration(labelText: 'Item Group', isDense: true, contentPadding: EdgeInsets.all(10)),
                            items: [const DropdownMenuItem(value: '', child: Text('All Item Groups')),
                              for (final group in groups) DropdownMenuItem(value: group, child: Text(group, overflow: TextOverflow.ellipsis))],
                            onChanged: (value) { if (value == null) return; setState(() { _itemGroup = value; _load(); }); },
                          )),
                          SizedBox(width: 190, child: TextFormField(
                            initialValue: _search,
                            decoration: const InputDecoration(hintText: 'Search item', prefixIcon: Icon(Icons.search, size: 18), isDense: true),
                            onChanged: (value) => setState(() => _search = value),
                          )),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: _desktopMetric('Item rows', formatAmount(rows.length), const Color(0xFFE3EFFC))),
                    const SizedBox(width: 8),
                    Expanded(child: _desktopMetric('Total Qty', formatAmount(qty), const Color(0xFFE8F6EF))),
                    const SizedBox(width: 8),
                    Expanded(child: _desktopMetric('Total Amount (MMK)', formatAmount(total), const Color(0xFFE3EFFC))),
                  ]),
                  const SizedBox(height: 10),
                  if (data['foc_detection_available'] != true)
                    const Padding(padding: EdgeInsets.only(bottom: 8), child: Text('FOC mapping is not configured or not detected in ERPNext. Verify the Sales Order/Sales Invoice FOC flag before relying on FOC Qty.', style: TextStyle(color: Colors.deepOrange, fontSize: 12))),
                  Expanded(child: Card(
                    color: Colors.white, margin: EdgeInsets.zero, clipBehavior: Clip.antiAlias,
                    child: Column(children: [
                      _desktopRow('Item Name', 'Rate', 'Qty', 'FOC Qty', 'Amount', header: true),
                      Expanded(child: rows.isEmpty ? const Center(child: Text('No sales items for these filters.')) : ListView.builder(
                        itemCount: rows.length,
                        itemBuilder: (context, index) {
                          final row = rows[index];
                          return _desktopRow(
                            row['item_name']?.toString() ?? '',
                            formatAmount(_num(row['rate'])),
                            formatAmount(_num(row['qty'])),
                            formatAmount(_num(row['foc_qty'])),
                            formatAmount(_num(row['amount'])),
                            alternate: index.isOdd,
                          );
                        },
                      )),
                      _desktopRow('Total', '', formatAmount(qty), formatAmount(rows.fold<double>(0, (sum, row) => sum + _num(row['foc_qty']))), formatAmount(total), header: true),
                    ]),
                  )),
                  const SizedBox(height: 6),
                  const Text('Amount (MMK) · Qty includes FOC; do not add FOC Qty again.', style: TextStyle(fontSize: 12, color: Colors.black54)),
                ],
              ),
            );
          }
          return ListView(padding: const EdgeInsets.fromLTRB(12, 20, 12, 24), children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('Counter',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            ),
            DropdownButtonFormField<String>(
              key: ValueKey('counter-$_counter'),
              initialValue: counters.contains(_counter) ? _counter : '',
              isExpanded: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
              items: [
                const DropdownMenuItem(value: '', child: Text('All Counters')),
                for (final name in counters)
                  DropdownMenuItem(value: name, child: Text(name,
                    overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _counter = value;
                  _itemGroup = '';
                  _load();
                });
              },
            ),
            const SizedBox(height: 16),
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('Item Group',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            ),
            DropdownButtonFormField<String>(
              key: ValueKey('group-$_counter-$_itemGroup'),
              initialValue: groups.contains(_itemGroup) ? _itemGroup : '',
              isExpanded: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              items: [
                const DropdownMenuItem(value: '', child: Text('All Item Groups')),
                for (final group in groups)
                  DropdownMenuItem(
                    value: group,
                    child: Text(group, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _itemGroup = value;
                  _load();
                });
              },
            ),
            const SizedBox(height: 16),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Search Item', prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder()),
              onChanged: (value) => setState(() => _search = value),
            ),
            const SizedBox(height: 10),
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
            if (rows.isNotEmpty)
              Card(
                margin: EdgeInsets.zero,
                clipBehavior: Clip.antiAlias,
                child: Table(
                  columnWidths: const {
                    0: FlexColumnWidth(5),
                    1: FixedColumnWidth(54),
                    2: FlexColumnWidth(3),
                  },
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  border: TableBorder(
                    horizontalInside: BorderSide(
                      color: Theme.of(context).dividerColor,
                      width: 0.5,
                    ),
                  ),
                  children: [
                    TableRow(
                      decoration: BoxDecoration(
                        color: const Color(0xFF205F91),
                      ),
                      children: const [
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 13),
                          child: Text('Item Name',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            )),
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 13),
                          child: Text('Qty',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            )),
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 13),
                          child: Text('Amount',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            )),
                        ),
                      ],
                    ),
                    for (final row in rows)
                      TableRow(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${row['item_name']?.toString() ?? ''} @${formatAmount(_num(row['rate']))}',
                                  style: const TextStyle(fontWeight: FontWeight.w500),
                                ),
                                if (_num(row['foc_qty']) != 0)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 3),
                                    child: Text(
                                      'FOC Qty: ${formatAmount(_num(row['foc_qty']))}',
                                      style: TextStyle(
                                        color: const Color(0xFF16834B),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
                            child: Text(
                              formatAmount(_num(row['qty'])),
                              textAlign: TextAlign.right,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            child: Text(
                              formatAmount(_num(row['amount'])),
                              textAlign: TextAlign.right,
                            ),
                          ),
                        ],
                      ),
                    TableRow(
                      decoration: BoxDecoration(
                        color: const Color(0xFF205F91),
                      ),
                      children: [
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                          child: Text('Total',
                            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
                          child: Text(formatAmount(qty),
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                          child: Text(formatAmount(total),
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            const Text('Amount (MMK) · Qty includes FOC; do not add FOC Qty again.',
              style: TextStyle(fontSize: 12, color: Colors.black54)),
          ]);
        },
      )),
    ]),
  );
  }

  Widget _desktopMetric(String title, String value, Color background) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 12, color: Color(0xFF315F8E))),
        const SizedBox(height: 4),
        Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: Color(0xFF153D69))),
      ]),
    );
  }

  Widget _desktopRow(String name, String rate, String qty, String foc, String amount, {bool header = false, bool alternate = false}) {
    final style = TextStyle(fontSize: 12, color: header ? Colors.white : const Color(0xFF173A5E), fontWeight: header ? FontWeight.w700 : FontWeight.w500);
    Widget cell(String value, int flex, {bool numeric = true}) => Expanded(
      flex: flex,
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 5),
        child: Tooltip(message: value, child: Text(value, maxLines: numeric ? 1 : 2, overflow: TextOverflow.ellipsis, textAlign: numeric ? TextAlign.right : TextAlign.left, style: style))),
    );
    return Container(
      color: header ? const Color(0xFF205F91) : alternate ? const Color(0xFFF4F7FB) : Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
      child: Row(children: [cell(name, 5, numeric: false), cell(rate, 2), cell(qty, 1), cell(foc, 1), cell(amount, 2)]),
    );
  }
}
