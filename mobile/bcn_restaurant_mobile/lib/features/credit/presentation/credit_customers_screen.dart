import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatters/amount_format.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/credit_repository.dart';

final creditRepositoryProvider = Provider<CreditRepository>(
  (ref) => CreditRepository(ref.watch(apiClientProvider)),
);

class CreditCustomersScreen extends ConsumerStatefulWidget {
  const CreditCustomersScreen({super.key});

  @override
  ConsumerState<CreditCustomersScreen> createState() => _CreditCustomersScreenState();
}

class _CreditCustomersScreenState extends ConsumerState<CreditCustomersScreen> {
  late Future<List<CreditCustomer>> _customers;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _customers = ref.read(creditRepositoryProvider).customers();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Credit Customers'),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Search customer',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (value) => setState(() => _search = value.toLowerCase()),
              ),
            ),
            Expanded(
              child: FutureBuilder<List<CreditCustomer>>(
                future: _customers,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return _error(context, snapshot.error.toString(), _refresh);
                  }
                  final all = snapshot.data ?? const <CreditCustomer>[];
                  final visible = all.where((c) =>
                      c.customer.toLowerCase().contains(_search) ||
                      c.customerName.toLowerCase().contains(_search)).toList();
                  final total = all.fold<double>(0, (sum, c) => sum + c.outstanding);
                  return RefreshIndicator(
                    onRefresh: () async {
                      _refresh();
                      await _customers;
                    },
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                      children: [
                        Card(
                          child: ListTile(
                            title: const Text('Total Outstanding'),
                            subtitle: Text('${all.length} customers'),
                            trailing: Text(
                              formatMoney(total, 'MMK'),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                        ),
                        if (visible.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(32),
                            child: Center(child: Text('No credit customers found')),
                          ),
                        for (final customer in visible)
                          Card(
                            child: ListTile(
                              title: Text(customer.customerName.isEmpty
                                  ? customer.customer : customer.customerName),
                              subtitle: Text('${customer.invoiceCount} unpaid invoice(s)'),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(formatMoney(customer.outstanding, customer.currency)),
                                  const Icon(Icons.chevron_right, size: 18),
                                ],
                              ),
                              onTap: () async {
                                await Navigator.of(context).push(MaterialPageRoute<void>(
                                  builder: (_) => _CreditDetailsScreen(customer: customer),
                                ));
                                if (mounted) _refresh();
                              },
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      );
}

class _CreditDetailsScreen extends ConsumerStatefulWidget {
  const _CreditDetailsScreen({required this.customer});
  final CreditCustomer customer;

  @override
  ConsumerState<_CreditDetailsScreen> createState() => _CreditDetailsScreenState();
}

class _CreditDetailsScreenState extends ConsumerState<_CreditDetailsScreen> {
  late Future<List<CreditInvoice>> _invoices;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _invoices = ref.read(creditRepositoryProvider).invoices(widget.customer.customer);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.customer.customerName)),
        body: FutureBuilder<List<CreditInvoice>>(
          future: _invoices,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _error(context, snapshot.error.toString(), _reload);
            }
            final invoices = snapshot.data ?? const <CreditInvoice>[];
            final outstanding = invoices.fold<double>(0, (sum, inv) => sum + inv.outstanding);
            return RefreshIndicator(
              onRefresh: () async {
                _reload();
                await _invoices;
              },
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  Card(
                    child: ListTile(
                      title: const Text('Remaining Credit'),
                      subtitle: Text(widget.customer.customer),
                      trailing: Text(
                        formatMoney(outstanding, widget.customer.currency),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ),
                  if (invoices.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          icon: const Icon(Icons.payments_outlined),
                          label: const Text('Receive Customer Payment'),
                          onPressed: () async {
                            final paid = await showDialog<bool>(
                              context: context,
                              barrierDismissible: false,
                              builder: (_) => _ReceivePaymentDialog(
                                customer: widget.customer.customer,
                                outstanding: outstanding,
                                currency: widget.customer.currency,
                                repository: ref.read(creditRepositoryProvider),
                              ),
                            );
                            if (paid == true && mounted) _reload();
                          },
                        ),
                      ),
                    ),
                  if (invoices.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: Text('No outstanding invoices')),
                    ),
                  for (final invoice in invoices)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(invoice.name, style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 8),
                            Text('Invoice date: ${invoice.postingDate}'),
                            Text('Due date: ${invoice.dueDate}'),
                            Text('Total: ${formatMoney(invoice.grandTotal, invoice.currency)}'),
                            Text('Outstanding: ${formatMoney(invoice.outstanding, invoice.currency)}'),

                          ],
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      );
}

class _ReceivePaymentDialog extends StatefulWidget {
  const _ReceivePaymentDialog({
    required this.customer,
    required this.outstanding,
    required this.currency,
    required this.repository,
  });
  final String customer;
  final double outstanding;
  final String currency;
  final CreditRepository repository;

  @override
  State<_ReceivePaymentDialog> createState() => _ReceivePaymentDialogState();
}

class _ReceivePaymentDialogState extends State<_ReceivePaymentDialog> {
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  String? _mode;
  late Future<List<CreditPaymentMode>> _modes;
  List<CreditPaymentMode> _availableModes = const [];
  bool _busy = false;
  String? _errorMessage;
  late final String _requestId =
      'credit-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(0x7fffffff)}';

  @override
  void initState() {
    super.initState();
    _loadModes();
  }

  void _loadModes() {
    setState(() {
      _mode = null;
      _availableModes = const [];
      _modes = widget.repository.paymentModes();
    });
  }

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amount.text.replaceAll(',', '').trim());
    if (amount == null || !amount.isFinite || amount <= 0 ||
        amount > widget.outstanding) {
      setState(() => _errorMessage = 'Enter an amount greater than 0 and not above outstanding.');
      return;
    }
    final selectedMode = _availableModes.where((m) => m.name == _mode).firstOrNull;
    if (selectedMode == null) {
      setState(() => _errorMessage = 'Please select a Mode of Payment.');
      return;
    }
    if (selectedMode.requiresReference && _reference.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Bank payment reference is required.');
      return;
    }
    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    try {
      final response = await widget.repository.receive(
        customer: widget.customer,
        amount: amount,
        modeOfPayment: selectedMode.name,
        requestId: _requestId,
        referenceNo: _reference.text.trim(),
      );
      if (response['success'] != true) {
        throw StateError(response['message']?.toString() ?? 'Payment failed');
      }
      if (!mounted) return;
      final payment = response['payment_entry']?.toString() ?? '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Payment received · $payment')),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() => _errorMessage = '$error\nCheck ERPNext before retrying this request.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final amount = double.tryParse(_amount.text.replaceAll(',', '').trim()) ?? 0;
    return AlertDialog(
      title: const Text('Receive Customer Payment'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Outstanding: ${formatMoney(widget.outstanding, widget.currency)}'),
            const SizedBox(height: 12),
            TextField(
              controller: _amount,
              enabled: !_busy,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Payment amount'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            FutureBuilder<List<CreditPaymentMode>>(
              future: _modes,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 12),
                        Text('Loading payment modes...'),
                      ],
                    ),
                  );
                }
                if (snapshot.hasError) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Could not load payment modes: ${snapshot.error}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      TextButton(
                        onPressed: _busy ? null : _loadModes,
                        child: const Text('Retry'),
                      ),
                    ],
                  );
                }
                final modes = snapshot.data ?? const <CreditPaymentMode>[];
                _availableModes = modes;
                if (modes.isEmpty) {
                  return const Text(
                    'No Cash/Bank payment modes configured in ERPNext.',
                  );
                }
                return DropdownButtonFormField<String>(
                  value: modes.any((m) => m.name == _mode) ? _mode : null,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Mode of Payment',
                  ),
                  hint: const Text('Select payment mode'),
                  items: modes
                      .map((mode) => DropdownMenuItem(
                            value: mode.name,
                            child: Text(mode.name),
                          ))
                      .toList(),
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _mode = value),
                );
              },
            ),
            if (_availableModes.any(
              (m) => m.name == _mode && m.requiresReference,
            )) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _reference,
                enabled: !_busy,
                decoration: const InputDecoration(labelText: 'Transaction reference'),
              ),
            ],
            const SizedBox(height: 12),
            Text('Remaining: ${formatMoney(
              (widget.outstanding - amount).clamp(0, double.infinity),
              widget.currency,
            )}'),
            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(_errorMessage!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy || _mode == null ? null : _submit,
          child: Text(_busy ? 'Processing...' : 'Confirm Payment'),
        ),
      ],
    );
  }
}

Widget _error(BuildContext context, String message, VoidCallback retry) =>
    Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: retry, child: const Text('Retry')),
          ],
        ),
      ),
    );
