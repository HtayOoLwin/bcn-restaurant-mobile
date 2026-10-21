import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// UI-only room charging prototype. No ERPNext calls, persistence or print jobs.
class RoomTimerDemoScreen extends StatefulWidget {
  const RoomTimerDemoScreen({super.key});

  @override
  State<RoomTimerDemoScreen> createState() => _RoomTimerDemoScreenState();
}

enum _RoomStage { available, ordering, billing, stopped, done }

class _RoomTimerDemoScreenState extends State<RoomTimerDemoScreen> {
  static const double _hourlyRate = 10000;
  static const double _foodRate = 12000;
  static const double _drinkRate = 2500;

  _RoomStage _stage = _RoomStage.available;
  DateTime? _startedAt;
  DateTime? _stoppedAt;
  Timer? _ticker;
  int _foodQty = 2;
  int _drinkQty = 1;
  bool? _printSelected;

  Duration get _elapsed {
    if (_startedAt == null) return Duration.zero;
    final until = _stoppedAt ?? DateTime.now();
    final difference = until.difference(_startedAt!);
    return difference.isNegative ? Duration.zero : difference;
  }

  int get _billableHours {
    if (_startedAt == null) return 0;
    return math.max(1, (_elapsed.inMilliseconds / 3600000).ceil());
  }

  double get _foodSubtotal => _foodQty * _foodRate + _drinkQty * _drinkRate;
  double get _tax => _foodSubtotal * .05;
  double get _service => _foodSubtotal * .10;
  double get _roomCharge => _billableHours * _hourlyRate;
  double get _grandTotal => _foodSubtotal + _tax + _service + _roomCharge;

  String _money(num amount) {
    final text = amount.round().toString();
    return text.replaceAllMapped(
      RegExp(r'\\B(?=(\\d{3})+(?!\\d))'),
      (_) => ',',
    );
  }

  String _duration(Duration duration) {
    final seconds = duration.inSeconds;
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final rest = seconds % 60;
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${rest.toString().padLeft(2, '0')}';
  }

  String _clock(DateTime? date) {
    if (date == null) return '—';
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    return '${hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')} '
        '${date.hour < 12 ? 'AM' : 'PM'}';
  }

  void _start() {
    setState(() {
      _startedAt = DateTime.now();
      _stoppedAt = null;
      _stage = _RoomStage.ordering;
      _printSelected = null;
    });
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _stage != _RoomStage.stopped && _stage != _RoomStage.done) {
        setState(() {});
      }
    });
  }

  Future<void> _requestBilling() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Proceed to Billing?'),
        content: const Text(
          'Food and drink ordering will be locked. '
          'The room timer will keep running until Stop Timer is pressed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) setState(() => _stage = _RoomStage.billing);
  }

  void _stop() {
    if (_stage != _RoomStage.billing) return;
    setState(() {
      _stoppedAt = DateTime.now();
      _stage = _RoomStage.stopped;
    });
    _ticker?.cancel();
  }

  void _choosePrint(bool print) {
    setState(() {
      _printSelected = print;
      _stage = _RoomStage.done;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(print
          ? 'Print selected (demo only — no printer job sent).'
          : 'Print skipped (demo only — no billing data saved).'),
    ));
  }

  void _reset() {
    _ticker?.cancel();
    setState(() {
      _stage = _RoomStage.available;
      _startedAt = null;
      _stoppedAt = null;
      _foodQty = 2;
      _drinkQty = 1;
      _printSelected = null;
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Widget _line(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: TextStyle(
              fontWeight: bold ? FontWeight.w800 : FontWeight.w400,
            )),
          ),
          Text(value, style: TextStyle(
            fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
          )),
        ],
      ),
    );
  }

  Widget _quantityRow(
    String name, int count, double price, ValueChanged<int> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text('${_money(price)} MMK',
                style: Theme.of(context).textTheme.bodySmall),
            ],
          )),
          IconButton.filledTonal(
            onPressed: count > 0 ? () => onChanged(count - 1) : null,
            icon: const Icon(Icons.remove),
          ),
          SizedBox(width: 30, child: Text('$count', textAlign: TextAlign.center)),
          IconButton.filled(
            onPressed: () => onChanged(count + 1),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final active = _stage == _RoomStage.ordering ||
        _stage == _RoomStage.billing;
    final stopped = _stage == _RoomStage.stopped ||
        _stage == _RoomStage.done;

    return Scaffold(
      appBar: AppBar(title: const Text('Room Timer · UI Prototype')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('VIP Room 01',
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  const Text('10,000 MMK / Hour · round up to full hour'),
                  const SizedBox(height: 10),
                  Chip(label: Text(switch (_stage) {
                    _RoomStage.available => 'Available',
                    _RoomStage.ordering => 'Ordering',
                    _RoomStage.billing => 'Billing · Ordering locked',
                    _RoomStage.stopped => 'Timer Stopped',
                    _RoomStage.done => 'Bill Ready',
                  })),
                  const SizedBox(height: 12),
                  Center(child: Column(children: [
                    Text('ROOM TIMER',
                      style: Theme.of(context).textTheme.labelMedium),
                    Text(_duration(_elapsed),
                      style: const TextStyle(fontSize: 36,
                        fontWeight: FontWeight.w800)),
                    Text(active ? 'Running' : stopped ? 'Stopped' : 'Not started'),
                  ])),
                  const SizedBox(height: 12),
                  _line('Start', _clock(_startedAt)),
                  _line('Stop', _clock(_stoppedAt)),
                  if (_startedAt != null)
                    _line('Room Charge ${active ? '(estimate)' : ''}',
                      '${_money(_roomCharge)} MMK'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_stage == _RoomStage.available)
            FilledButton.icon(
              onPressed: _start, icon: const Icon(Icons.play_arrow),
              label: const Text('Start Timer'),
            ),
          if (_stage == _RoomStage.ordering) ...[
            Card(child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Align(alignment: Alignment.centerLeft,
                    child: Text('Food & Drinks · Demo Items',
                      style: TextStyle(fontWeight: FontWeight.w800))),
                  _quantityRow('Fried Rice', _foodQty, _foodRate,
                    (v) => setState(() => _foodQty = v)),
                  _quantityRow('Soft Drink', _drinkQty, _drinkRate,
                    (v) => setState(() => _drinkQty = v)),
                  const Divider(),
                  _line('Food Subtotal', '${_money(_foodSubtotal)} MMK',
                    bold: true),
                ],
              ),
            )),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _requestBilling,
              icon: const Icon(Icons.receipt_long),
              label: const Text('Billing'),
            ),
          ],
          if (_stage == _RoomStage.billing) ...[
            const Card(child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Ordering is locked. The timer is still running. '
                  'Press Stop Timer to calculate the final room charge.'),
            )),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _stop, icon: const Icon(Icons.stop),
              label: const Text('Stop Timer'),
            ),
          ],
          if (stopped) ...[
            Card(child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                const Align(alignment: Alignment.centerLeft,
                  child: Text('Final Bill Summary',
                    style: TextStyle(fontSize: 18,
                      fontWeight: FontWeight.w800))),
                const SizedBox(height: 10),
                _line('Food Charges', _money(_foodSubtotal)),
                _line('Commercial Tax (5% on food)', _money(_tax)),
                _line('Service Charge (10% on food)', _money(_service)),
                const Divider(),
                _line('Actual Duration', _duration(_elapsed)),
                _line('Billable Hours', '$_billableHours'),
                _line('Room Charges', _money(_roomCharge)),
                const Divider(),
                _line('NET TOTAL', '${_money(_grandTotal)} MMK', bold: true),
              ]),
            )),
            const SizedBox(height: 12),
            if (_stage == _RoomStage.stopped) ...[
              const Center(child: Text('Do you want to print the bill?',
                style: TextStyle(fontWeight: FontWeight.w800))),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: FilledButton.icon(
                  onPressed: () => _choosePrint(true),
                  icon: const Icon(Icons.print),
                  label: const Text('Yes, Print'),
                )),
                const SizedBox(width: 12),
                Expanded(child: OutlinedButton(
                  onPressed: () => _choosePrint(false),
                  child: const Text('No, Skip'),
                )),
              ]),
            ] else
              ListTile(
                leading: const Icon(Icons.check_circle_outline),
                title: Text(_printSelected == true
                    ? 'Print selected (not sent)' : 'Printing skipped'),
                subtitle: const Text('Demo only · no server data saved'),
              ),
          ],
          const SizedBox(height: 16),
          Text(
            'LOCAL UI DEMO ONLY — timer, quantities and bill are held in '
            'memory. Restarting the app loses them. Existing ERPNext orders, '
            'invoices and printer jobs are unchanged.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _reset,
            icon: const Icon(Icons.restart_alt),
            label: const Text('Reset Demo'),
          ),
        ],
      ),
    );
  }
}
