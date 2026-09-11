import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/formatters/amount_format.dart';
import '../../../core/formatters/amount_input_formatter.dart';
import '../../../core/search/order_search.dart';
import '../../../core/widgets/operational_refresh_indicator.dart';
import '../../../core/widgets/order_search_field.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../printing/data/windows_print_repository.dart';
import '../../waiter/presentation/waiter_tables_screen.dart';
import '../data/cashier_repository.dart';
import '../domain/cashier_models.dart';

final cashierRepositoryProvider = Provider<CashierRepository>(
  (ref) => CashierRepository(ref.watch(apiClientProvider)),
);

final cashierBillingProvider = FutureProvider<CashierBillingResponse>(
  (ref) => ref.watch(cashierRepositoryProvider).getBilling(),
);

typedef CashierPrintRequestIdFactory = String Function();

final cashierPrintRequestIdFactoryProvider =
    Provider<CashierPrintRequestIdFactory>((ref) => _newPrintRequestId);

String _newPrintRequestId() {
  final entropy = Random.secure().nextInt(0x7fffffff).toRadixString(16);
  return 'cashier-${DateTime.now().microsecondsSinceEpoch}-$entropy';
}

class CashierScreen extends ConsumerStatefulWidget {
  const CashierScreen({super.key});

  @override
  ConsumerState<CashierScreen> createState() => _CashierScreenState();
}

class _CashierScreenState extends ConsumerState<CashierScreen> {
  String _searchQuery = '';
  final Set<String> _pendingPrintSalesOrders = {};
  final Map<String, String> _retryPrintRequestIds = {};
  CashierPaymentResult? _lastPaymentResult;
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();

    _autoRefreshTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) {
        if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
        if (_pendingPrintSalesOrders.isNotEmpty) return;

        final current = ref.read(cashierBillingProvider);
        if (current.isLoading) return;

        ref.invalidate(cashierBillingProvider);
      },
    );
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bootstrap = ref.watch(authControllerProvider).asData?.value.bootstrap;
    final billing = ref.watch(cashierBillingProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          bootstrap?.fullName.isNotEmpty == true
              ? bootstrap!.fullName
              : 'Cashier',
        ),
        actions: [
          if (bootstrap?.permissions.waiter == true)
            IconButton(
              tooltip: 'Waiter',
              onPressed: () => context.go('/tables'),
              icon: const Icon(Icons.table_restaurant),
            ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(cashierBillingProvider),
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: () => context.push('/settings'),
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
      body: Column(
        children: [
          OperationalRefreshIndicator(
            onRefresh: () => ref.invalidate(cashierBillingProvider),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: OrderSearchField(
              query: _searchQuery,
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),
          if (_lastPaymentResult != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Payment completed'),
                            const SizedBox(height: 2),
                            Text(_lastPaymentResult!.salesOrder),
                          ],
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: _pendingPrintSalesOrders.contains(
                          _lastPaymentResult!.salesOrder,
                        )
                            ? null
                            : () => _printBill(
                                  context: context,
                                  salesOrder: _lastPaymentResult!.salesOrder,
                                ),
                        icon: const Icon(Icons.print),
                        label: const Text('Reprint Bill'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Expanded(
            child: billing.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(error.toString(), textAlign: TextAlign.center),
                ),
              ),
              data: (data) {
                final filteredBills = data.bills
                    .where(
                      (bill) => matchesOrderSearch(
                        queryText: _searchQuery,
                        tableName: bill.customerName,
                        orderNumbers: [bill.salesOrder],
                      ),
                    )
                    .toList();
                return RefreshIndicator(
                  onRefresh: () => ref.refresh(cashierBillingProvider.future),
                  child: data.bills.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 180),
                            Center(child: Text('No bills ready for payment.')),
                          ],
                        )
                      : filteredBills.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 180),
                            Center(child: Text('No bills match your search.')),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: filteredBills.length,
                          itemBuilder: (context, index) {
                            final bill = filteredBills[index];
                            return _BillCard(
                              bill: bill,
                              printPending: _pendingPrintSalesOrders.contains(
                                bill.salesOrder,
                              ),
                              onPrint: () => _printBill(
                                context: context,
                                salesOrder: bill.salesOrder,
                              ),
                              onPayment: () => _openPaymentSheet(
                                context: context,
                                ref: ref,
                                billing: data,
                                bill: bill,
                              ),
                            );
                          },
                        ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _printBill({
    required BuildContext context,
    required String salesOrder,
  }) async {
    if (_pendingPrintSalesOrders.contains(salesOrder)) return;

    final requestId =
        _retryPrintRequestIds[salesOrder] ??
        ref.read(cashierPrintRequestIdFactoryProvider)();

    setState(() => _pendingPrintSalesOrders.add(salesOrder));
    try {
      final result = await ref
          .read(windowsPrintRepositoryProvider)
          .requestCashierBill(
            salesOrder: salesOrder,
            requestId: requestId,
          );
      if (!mounted || !context.mounted) return;
      setState(() => _retryPrintRequestIds.remove(salesOrder));
      ref.invalidate(cashierBillingProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Print job sent · ${result.printJob}')),
      );
    } catch (error) {
      if (mounted) {
        setState(() => _retryPrintRequestIds[salesOrder] = requestId);
      }
      if (mounted && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) {
        setState(() => _pendingPrintSalesOrders.remove(salesOrder));
      }
    }
  }

  Future<void> _openPaymentSheet({
    required BuildContext context,
    required WidgetRef ref,
    required CashierBillingResponse billing,
    required CashierBill bill,
  }) async {
    if (bill.restaurantStatus.trim().toLowerCase() != 'billing') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please wait for Request for Bill first.')),
      );
      return;
    }

    final controllers = <String, TextEditingController>{};
    for (final mode in billing.modes) {
      controllers[mode.name] = TextEditingController();
    }

    final cashMode = _findModeByName(billing.modes, 'Cash');
    final kpayMode = _findModeByName(billing.modes, 'Kpay');
    final primaryMode =
        cashMode ?? (billing.modes.isNotEmpty ? billing.modes.first : null);
    final secondaryMode =
        kpayMode ?? _firstOtherMode(billing.modes, primaryMode?.name);

    bool busy = false;
    String selectedPaymentType = primaryMode?.name ?? '';
    final fullAmountText = formatAmount(bill.grandTotal);

    void setControllerAmount(TextEditingController? controller, double amount) {
      if (controller == null) return;
      final text = amount <= 0 ? '' : formatAmount(amount);
      controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }

    void setPaymentType(String type) {
      selectedPaymentType = type;
      for (final controller in controllers.values) {
        controller.clear();
      }
      final target = type == 'Split'
          ? (primaryMode == null ? null : controllers[primaryMode.name])
          : controllers[type];
      if (target != null) {
        target.value = TextEditingValue(
          text: fullAmountText,
          selection: TextSelection.collapsed(offset: fullAmountText.length),
        );
      }
    }

    void onTenderChanged(String changedMode) {
      if (selectedPaymentType != 'Split' ||
          primaryMode == null ||
          secondaryMode == null ||
          changedMode != secondaryMode.name) {
        return;
      }

      final secondAmount = _parseTender(controllers[secondaryMode.name]?.text);
      final balance = (bill.grandTotal - secondAmount)
          .clamp(0, double.infinity)
          .toDouble();
      setControllerAmount(controllers[primaryMode.name], balance);
    }

    if (selectedPaymentType.isNotEmpty) {
      setPaymentType(selectedPaymentType);
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _PaymentControllerOwner(
        controllers: controllers,
        child: StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final visibleModes = <CashierPaymentMode>[];
            if (selectedPaymentType == 'Split') {
              if (primaryMode != null) visibleModes.add(primaryMode);
              if (secondaryMode != null &&
                  secondaryMode.name != primaryMode?.name) {
                visibleModes.add(secondaryMode);
              }
            } else {
              final selectedMode = _findModeByName(
                billing.modes,
                selectedPaymentType,
              );
              if (selectedMode != null) visibleModes.add(selectedMode);
            }

            final tenders = <CashierPaymentTender>[];
            var totalTendered = 0.0;
            var nonCashTotal = 0.0;
            var cashTendered = 0.0;

            for (final mode in visibleModes) {
              final amount = _parseTender(controllers[mode.name]?.text);
              if (amount <= 0) continue;
              tenders.add(
                CashierPaymentTender(modeOfPayment: mode.name, amount: amount),
              );
              totalTendered += amount;
              if (_isCashMode(mode.name)) {
                cashTendered += amount;
              } else {
                nonCashTotal += amount;
              }
            }

            final remaining = totalTendered < bill.grandTotal
                ? bill.grandTotal - totalTendered
                : 0.0;
            final change = totalTendered > bill.grandTotal
                ? totalTendered - bill.grandTotal
                : 0.0;
            final nonCashOver = nonCashTotal > bill.grandTotal + 0.0001;
            final overWithoutCash = change > 0 && cashTendered <= 0;
            final canPay =
                tenders.isNotEmpty &&
                remaining <= 0.0001 &&
                !nonCashOver &&
                !overWithoutCash &&
                !busy;

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  20,
                  20,
                  20 + MediaQuery.viewInsetsOf(sheetContext).bottom,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${bill.customerName} · ${bill.salesOrder}',
                        style: Theme.of(sheetContext).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Amount Due: ${formatMoney(bill.grandTotal, bill.currency)}',
                        style: Theme.of(sheetContext).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Payment Type',
                        style: Theme.of(sheetContext).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ...billing.modes.map(
                            (mode) => ChoiceChip(
                              label: Text(mode.name),
                              selected: selectedPaymentType == mode.name,
                              onSelected: busy
                                  ? null
                                  : (_) => setSheetState(
                                      () => setPaymentType(mode.name),
                                    ),
                            ),
                          ),
                          if (primaryMode != null && secondaryMode != null)
                            ChoiceChip(
                              label: const Text('Split'),
                              selected: selectedPaymentType == 'Split',
                              onSelected: busy
                                  ? null
                                  : (_) => setSheetState(
                                      () => setPaymentType('Split'),
                                    ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      ...visibleModes.map(
                        (mode) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: TextField(
                            controller: controllers[mode.name],
                            enabled: !busy,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: const [
                              ThousandsSeparatorInputFormatter(),
                            ],
                            decoration: InputDecoration(
                              labelText: mode.name,
                              suffixText: bill.currency,
                              border: const OutlineInputBorder(),
                            ),
                            onChanged: (_) =>
                                setSheetState(() => onTenderChanged(mode.name)),
                          ),
                        ),
                      ),
                      _AmountSummaryRow(
                        label: 'Total Tendered',
                        value: formatMoney(totalTendered, bill.currency),
                      ),
                      _AmountSummaryRow(
                        label: 'Remaining',
                        value: formatMoney(remaining, bill.currency),
                      ),
                      _AmountSummaryRow(
                        label: 'Change',
                        value: formatMoney(change, bill.currency),
                        emphasize: change > 0,
                      ),
                      if (nonCashOver)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            'Non-cash payment cannot exceed the outstanding amount.',
                          ),
                        ),
                      if (overWithoutCash)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            'Only Cash can include an amount that will be returned as change.',
                          ),
                        ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: !canPay
                            ? null
                            : () async {
                                setSheetState(() => busy = true);
                                try {
                                  final result = await ref
                                      .read(cashierRepositoryProvider)
                                      .paySplit(
                                        salesOrder: bill.salesOrder,
                                        payments: tenders,
                                      );
                                  if (mounted) {
                                    setState(() {
                                      _retryPrintRequestIds.remove(
                                        result.salesOrder,
                                      );
                                      _lastPaymentResult = result;
                                    });
                                  }
                                  ref.invalidate(cashierBillingProvider);
                                  ref.invalidate(tablesProvider('dine_in'));
                                  ref.invalidate(tablesProvider('takeaway'));
                                  if (sheetContext.mounted) {
                                    Navigator.of(sheetContext).pop();
                                  }
                                  if (context.mounted) {
                                    final entries = result.paymentEntries.join(', ');
                                    final changeText = result.changeAmount > 0
                                        ? ' · Change ${formatMoney(result.changeAmount, bill.currency)}'
                                        : '';
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          entries.isNotEmpty
                                              ? 'Payment completed · $entries$changeText'
                                              : 'Payment completed$changeText',
                                        ),
                                      ),
                                    );
                                  }
                                } catch (error) {
                                  if (sheetContext.mounted) {
                                    setSheetState(() => busy = false);
                                    ScaffoldMessenger.of(
                                      sheetContext,
                                    ).showSnackBar(
                                      SnackBar(content: Text(error.toString())),
                                    );
                                  }
                                }
                              },
                        icon: busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.payments),
                        label: Text(busy ? 'Processing…' : 'Confirm Payment'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PaymentControllerOwner extends StatefulWidget {
  const _PaymentControllerOwner({
    required this.controllers,
    required this.child,
  });

  final Map<String, TextEditingController> controllers;
  final Widget child;

  @override
  State<_PaymentControllerOwner> createState() => _PaymentControllerOwnerState();
}

class _PaymentControllerOwnerState extends State<_PaymentControllerOwner> {
  @override
  void dispose() {
    for (final controller in widget.controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _AmountSummaryRow extends StatelessWidget {
  const _AmountSummaryRow({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value,
            style: emphasize ? Theme.of(context).textTheme.titleMedium : null,
          ),
        ],
      ),
    );
  }
}

class _BillCard extends StatelessWidget {
  const _BillCard({
    required this.bill,
    required this.printPending,
    required this.onPrint,
    required this.onPayment,
  });

  final CashierBill bill;
  final bool printPending;
  final VoidCallback onPrint;
  final VoidCallback onPayment;

  @override
  Widget build(BuildContext context) {
    final hasPrinted = bill.lastPrintJob?.isNotEmpty == true;
    final isBilling = bill.restaurantStatus.trim().toLowerCase() == 'billing';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bill.customerName,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        bill.salesOrder,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Chip(label: Text(bill.restaurantStatus)),
              ],
            ),
            if (bill.lastPrintStatus?.isNotEmpty == true) ...[
              const SizedBox(height: 6),
              Text('Last Print: ${bill.lastPrintStatus}'),
            ],
            const Divider(height: 24),
            ...bill.items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        '${formatQuantity(item.qty)} × ${item.itemName}',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(formatMoney(item.amount, bill.currency)),
                  ],
                ),
              ),
            ),
            const Divider(height: 24),
            _AmountSummaryRow(
              label: 'Subtotal',
              value: formatMoney(bill.netTotal, bill.currency),
            ),
            ...bill.taxes.map(
              (tax) => _AmountSummaryRow(
                label: tax.rate == 0
                    ? tax.description
                    : '${tax.description} ${formatQuantity(tax.rate)}%',
                value: formatMoney(tax.taxAmount, bill.currency),
              ),
            ),
            const SizedBox(height: 4),
            _AmountSummaryRow(
              label: 'Grand Total',
              value: formatMoney(bill.grandTotal, bill.currency),
              emphasize: true,
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                FilledButton.icon(
                  onPressed: isBilling && !printPending ? onPrint : null,
                  icon: printPending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.print),
                  label: Text(
                    printPending
                        ? 'Sending…'
                        : isBilling || hasPrinted
                        ? 'Reprint Bill'
                        : 'Print Bill',
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: isBilling ? onPayment : null,
                  icon: const Icon(Icons.point_of_sale),
                  label: const Text('Payment'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

double _parseTender(String? value) {
  return double.tryParse((value ?? '').replaceAll(',', '').trim()) ?? 0;
}

bool _isCashMode(String mode) => mode.trim().toLowerCase() == 'cash';

CashierPaymentMode? _findModeByName(
  List<CashierPaymentMode> modes,
  String name,
) {
  final wanted = name.trim().toLowerCase();
  for (final mode in modes) {
    if (mode.name.trim().toLowerCase() == wanted) return mode;
  }
  return null;
}

CashierPaymentMode? _firstOtherMode(
  List<CashierPaymentMode> modes,
  String? excludedName,
) {
  for (final mode in modes) {
    if (mode.name != excludedName) return mode;
  }
  return null;
}
