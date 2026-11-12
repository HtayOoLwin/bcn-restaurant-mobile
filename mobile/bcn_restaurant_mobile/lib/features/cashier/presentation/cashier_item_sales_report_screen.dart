import 'package:flutter/material.dart';

import '../../../core/formatters/amount_format.dart';
import '../data/cashier_repository.dart';

/// Read-only item sales report. The server owns all sales/FOC/PC calculations.
class CashierItemSalesReportScreen extends StatefulWidget {
  const CashierItemSalesReportScreen({super.key, required this.repository});

  final CashierRepository repository;

  @override
  State<CashierItemSalesReportScreen> createState() =>
      _CashierItemSalesReportScreenState();
}

class _CashierItemSalesReportScreenState
    extends State<CashierItemSalesReportScreen> {
  DateTime _selectedDate = DateTime.now();
  late Future<Map<String, dynamic>> _report;
  bool _showDetails = false;
  String _filter = 'All';
  String _selectedCounter = '';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _dateValue(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  String _displayDate(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/'
      '${value.month.toString().padLeft(2, '0')}/${value.year}';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _report = widget.repository.getItemSalesReport(_dateValue(_selectedDate));
  }

  Future<void> _chooseDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _selectedDate = picked;
      _reload();
    });
  }

  double _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  bool _matches(Map<String, dynamic> row, bool details) {
    final counterName = row['counter']?.toString() ?? '';
    if (_selectedCounter.isNotEmpty && counterName != _selectedCounter) {
      return false;
    }
    final query = _searchQuery.trim().toLowerCase();
    if (query.isNotEmpty) {
      final searchable = [
        row['item_code'],
        row['item_name'],
        row['counter'],
      ].map((value) => (value ?? '').toString().toLowerCase()).join(' ');
      if (!searchable.contains(query)) return false;
    }
    if (_filter == 'All') return true;
    if (_filter == 'FOC') {
      return details ? row['foc'] == true : _number(row['foc_qty']) > 0;
    }
    if (_filter == 'Parcel') {
      return details ? row['parcel'] == true : _number(row['parcel_qty']) > 0;
    }
    return details
        ? row['flags_linked'] == true && row['foc'] != true
        : _number(row['sales_qty']) > 0;
  }

  Widget _metric(String caption, String value, IconData icon) {
    return Card(
      color: const Color(0xFFEAF1F9),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 19, color: const Color(0xFF1B5C8E)),
              const SizedBox(width: 6),
              Expanded(child: Text(caption,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12))),
            ]),
            const SizedBox(height: 8),
            Text(value, style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 19)),
          ],
        ),
      ),
    );
  }

  Widget _numberColumn(String label, String value, {bool bold = false}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Text(label, style: const TextStyle(fontSize: 11, color: Colors.black54)),
      Text(value, style: TextStyle(fontWeight:
          bold ? FontWeight.bold : FontWeight.w500)),
    ]);
  }

  Widget _summaryRow(Map<String, dynamic> row, String currency) {
    return Card(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(row['item_name']?.toString() ?? '',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          Text('${row['counter'] ?? ''} · ${row['item_code'] ?? ''} · ${row['uom'] ?? ''}',
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 10),
          Wrap(spacing: 20, runSpacing: 10, children: [
            _numberColumn('Total Qty',
                formatAmount(_number(row['total_qty']))),
            _numberColumn('Sales Qty',
                formatAmount(_number(row['sales_qty']))),
            _numberColumn('FOC Qty',
                formatAmount(_number(row['foc_qty']))),
            _numberColumn('PC Qty',
                formatAmount(_number(row['parcel_qty']))),
            _numberColumn('Avg Rate',
                formatMoney(_number(row['avg_rate']), currency)),
            _numberColumn('Sales Amount',
                formatMoney(_number(row['sales_amount']), currency), bold: true),
          ]),
          if (_number(row['unlinked_qty']) > 0)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Some invoice lines lack Sales Order FOC/PC links.',
                  style: TextStyle(color: Colors.deepOrange, fontSize: 12)),
            ),
        ]),
      ),
    );
  }

  Widget _detailRow(Map<String, dynamic> row, String currency) {
    final linked = row['flags_linked'] == true;
    final foc = row['foc'] == true;
    final parcel = row['parcel'] == true;
    return Card(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(row['item_name']?.toString() ?? '',
                style: const TextStyle(fontWeight: FontWeight.bold))),
            Text(formatMoney(_number(row['amount']), currency),
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 4),
          Text('${row['invoice'] ?? ''} · ${row['customer'] ?? ''} · ${row['counter'] ?? ''}',
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center,
              children: [
            Text('Qty: ${formatAmount(_number(row['qty']))} ${row['uom'] ?? ''}'),
            Text('Rate: ${formatMoney(_number(row['rate']), currency)}'),
            if (foc) const Chip(label: Text('FOC'), visualDensity: VisualDensity.compact),
            if (parcel) const Chip(label: Text('PC'), visualDensity: VisualDensity.compact),
            if (!linked)
              const Chip(label: Text('Unlinked'), visualDensity: VisualDensity.compact),
          ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Item Sales Report'), actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: () => setState(_reload),
          icon: const Icon(Icons.refresh),
        ),
      ]),
      body: Column(children: [
        Card(
          margin: const EdgeInsets.all(12),
          color: const Color(0xFF205F91),
          child: InkWell(
            onTap: _chooseDate,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                const Icon(Icons.calendar_month, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(child: Text(_displayDate(_selectedDate),
                    style: const TextStyle(color: Colors.white,
                        fontWeight: FontWeight.bold, fontSize: 16))),
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
                padding: const EdgeInsets.all(20),
                child: Text('Cannot load item sales report: ${snapshot.error}'),
              ));
            }
            final result = snapshot.data ?? <String, dynamic>{};
            final currency = result['currency']?.toString() ?? 'MMK';
            final rawRows = (result[_showDetails ? 'details' : 'summary'] as List?)
                ?? const [];
            final rows = rawRows
                .whereType<Map>()
                .map((row) => Map<String, dynamic>.from(row))
                .where((row) => _matches(row, _showDetails))
                .toList();
            final counterNames = ((result['counters'] as List?) ?? const [])
                .map((value) => value.toString())
                .where((value) => value.isNotEmpty)
                .toSet()
                .toList()..sort();
            final selectedCounter = counterNames.contains(_selectedCounter)
                ? _selectedCounter : '';
            final filteredDetails = ((result['details'] as List?) ?? const [])
                .whereType<Map>()
                .map((row) => Map<String, dynamic>.from(row))
                .where((row) => _matches(row, true))
                .toList();
            final shownQty = filteredDetails.fold<double>(
                0, (sum, row) => sum + _number(row['qty']));
            final shownFoc = filteredDetails.fold<double>(
                0, (sum, row) => sum + (row['foc'] == true ? _number(row['qty']) : 0));
            final shownParcel = filteredDetails.fold<double>(
                0, (sum, row) => sum + (row['parcel'] == true ? _number(row['qty']) : 0));
            final shownAmount = filteredDetails.fold<double>(
                0, (sum, row) => sum + _number(row['amount']));

            return ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
              children: [
                LayoutBuilder(builder: (context, constraints) {
                  final width = (constraints.maxWidth - 8) / 2;
                  return Wrap(spacing: 8, runSpacing: 8, children: [
                    SizedBox(width: width, child: _metric('Sales Amount',
                        formatMoney(shownAmount, currency),
                        Icons.account_balance_wallet_outlined)),
                    SizedBox(width: width, child: _metric('Total Qty',
                        formatAmount(shownQty),
                        Icons.inventory_2_outlined)),
                    SizedBox(width: width, child: _metric('FOC Qty',
                        formatAmount(shownFoc),
                        Icons.card_giftcard)),
                    SizedBox(width: width, child: _metric('Parcel Qty',
                        formatAmount(shownParcel),
                        Icons.shopping_bag_outlined)),
                  ]);
                }),
                const SizedBox(height: 14),
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    labelText: 'Search Item',
                    hintText: 'Item Name / Item Code / Kitchen Counter',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchQuery.isEmpty ? null : IconButton(
                      tooltip: 'Clear Search',
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                      icon: const Icon(Icons.clear),
                    ),
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (value) => setState(() => _searchQuery = value),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: selectedCounter,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Kitchen Counter',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.category_outlined),
                  ),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('All Counters')),
                    for (final group in counterNames)
                      DropdownMenuItem(value: group, child: Text(
                        group, overflow: TextOverflow.ellipsis,
                      )),
                  ],
                  onChanged: (value) => setState(
                    () => _selectedCounter = value ?? '',
                  ),
                ),
                const SizedBox(height: 14),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Item Summary')),
                    ButtonSegment(value: true, label: Text('Sales Details')),
                  ],
                  selected: {_showDetails},
                  onSelectionChanged: (value) {
                    setState(() => _showDetails = value.first);
                  },
                ),
                const SizedBox(height: 10),
                Wrap(spacing: 6, children: [
                  for (final choice in ['All', 'Normal', 'FOC', 'Parcel'])
                    ChoiceChip(
                      label: Text(choice),
                      selected: _filter == choice,
                      onSelected: (_) => setState(() => _filter = choice),
                    ),
                ]),
                const SizedBox(height: 10),
                if (_number(result['unlinked_qty']) > 0)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: Text(
                      'Warning: Some items are not linked to Sales Orders; '
                      'their FOC and PC status is unknown.',
                      style: TextStyle(color: Colors.deepOrange),
                    ),
                  ),
                if (rows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('No items for this date / filter.')),
                  ),
                for (final row in rows)
                  _showDetails ? _detailRow(row, currency) : _summaryRow(row, currency),
                const SizedBox(height: 12),
                const Text(
                  'Sales Amount uses invoice item net amounts (before '
                  'invoice-level discounts and taxes). FOC and PC quantities '
                  'may overlap; do not add them to Total Qty.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            );
          },
        )),
      ]),
    );
  }
}
