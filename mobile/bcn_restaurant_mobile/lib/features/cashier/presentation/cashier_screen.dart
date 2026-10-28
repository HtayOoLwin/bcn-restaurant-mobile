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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.invalidate(cashierBillingProvider);
    });

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
            onPressed: () async {
              await context.push('/settings');
              if (!mounted) return;
              ref.invalidate(cashierBillingProvider);
            },
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
                              onPayment: () => _prepareAndOpenPayment(
                                context: context,
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

  Future<void> _prepareAndOpenPayment({
    required BuildContext context,
    required CashierBillingResponse billing,
    required CashierBill bill,
  }) async {
    final status = bill.restaurantStatus.trim().toLowerCase();
    if (status != 'billing' && status != 'payment pending') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Waiter must Request for Bill first.')),
      );
      return;
    }
    try {
      if (status == 'billing') {
        final prepared = await ref
            .read(cashierRepositoryProvider)
            .preparePayment(bill.salesOrder);
        final draftInvoice = prepared['sales_invoice']?.toString() ?? '';
        if (draftInvoice.isEmpty) {
          throw StateError(
            'Draft Sales Invoice was not returned. Payment has not started.',
          );
        }
        ref.invalidate(cashierBillingProvider);
      }
      if (!mounted || !context.mounted) return;
      await _openPaymentSheet(
        context: context,
        ref: ref,
        billing: billing,
        bill: bill,
      );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    }
  }

  Future<void> _openPaymentSheet({
    required BuildContext context,
    required WidgetRef ref,
    required CashierBillingResponse billing,
    required CashierBill bill,
  }) async {
    if (bill.restaurantStatus.trim().toLowerCase() != 'billing' &&
        bill.restaurantStatus.trim().toLowerCase() != 'payment pending') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please wait for Request for Bill first.')),
      );
      return;
    }

    final controllers = <String, TextEditingController>{};
    final discountController = TextEditingController();
    controllers['__discount__'] = discountController;
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
    double discountAmount() => _parseTender(discountController.text);
    double amountDue() => (bill.grandTotal - discountAmount()).clamp(0, double.infinity).toDouble();
    bool discountValid() => discountAmount() >= 0 && discountAmount() < bill.grandTotal && !discountController.text.contains('-');

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
      for (final entry in controllers.entries) {
        if (entry.key != '__discount__') entry.value.clear();
      }
      final target = type == 'Split'
          ? (primaryMode == null ? null : controllers[primaryMode.name])
          : controllers[type];
      if (target != null) {
        target.value = TextEditingValue(
          text: formatAmount(amountDue()),
          selection: TextSelection.collapsed(offset: formatAmount(amountDue()).length),
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
      final balance = (amountDue() - secondAmount)
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

            final payable = amountDue();
            final validDiscount = discountValid();
            final remaining = totalTendered < payable
                ? payable - totalTendered
                : 0.0;
            final change = totalTendered > payable
                ? totalTendered - payable
                : 0.0;
            final nonCashOver = nonCashTotal > payable + 0.0001;
            final overWithoutCash = change > 0 && cashTendered <= 0;
            final canPay =
                validDiscount &&
                payable > 0 &&
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
                        'Discount applies to the Draft Sales Invoice only.',
                        style: Theme.of(sheetContext).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      _AmountSummaryRow(
                        label: 'Original Total',
                        value: formatMoney(bill.grandTotal, bill.currency),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: discountController,
                        enabled: !busy,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: const [ThousandsSeparatorInputFormatter()],
                        decoration: InputDecoration(
                          labelText: 'Discount Amount',
                          hintText: '0',
                          suffixText: bill.currency,
                          border: const OutlineInputBorder(),
                          errorText: validDiscount ? null : 'Discount must be less than Grand Total',
                        ),
                        onChanged: (_) => setSheetState(() {
                          setPaymentType(selectedPaymentType);
                        }),
                      ),
                      const SizedBox(height: 8),
                      _AmountSummaryRow(label: 'Net Payable', value: formatMoney(payable, bill.currency), emphasize: true),
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
                                      .confirmPayment(
                                        salesOrder: bill.salesOrder,
                                        payments: tenders,
                                        discountAmount: discountAmount(),
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

const _billingCardColor = Color(0xFFE9F8EF);
const _openCardColor = Colors.white;
const _billingStatusBackground = Color(0xFFDDF5E7);
const _billingStatusForeground = Color(0xFF0B6B3A);
const _openStatusBackground = Color(0xFFF1F5F9);
const _openStatusForeground = Color(0xFF475569);
const _reprintBlue = Color(0xFF0D47A1);
const _paymentGreen = Color(0xFF0B6B3A);
const _disabledBackground = Color(0xFFE2E8F0);
const _disabledForeground = Color(0xFF94A3B8);

class _BillCard extends StatefulWidget {
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
  State<_BillCard> createState() => _BillCardState();
}

class _BillCardState extends State<_BillCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final bill = widget.bill;
    final isBilling = bill.restaurantStatus.trim().toLowerCase() == 'billing' ||
        bill.restaurantStatus.trim().toLowerCase() == 'payment pending';
    final cardColor = isBilling ? _billingCardColor : _openCardColor;
    final statusBackground =
        isBilling ? _billingStatusBackground : _openStatusBackground;
    final statusForeground =
        isBilling ? _billingStatusForeground : _openStatusForeground;

    final orderDetails = InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => setState(() => _expanded = !_expanded),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    bill.customerName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  color: statusForeground,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Tooltip(
              message: bill.salesOrder,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFE3EFFC),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  bill.salesOrder,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF153D69),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    final statusChip = Chip(
      avatar: Icon(
        isBilling ? Icons.receipt_long : Icons.schedule,
        size: 18,
        color: statusForeground,
      ),
      label: Text(
        bill.restaurantStatus,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: statusForeground,
          fontWeight: FontWeight.w600,
        ),
      ),
      backgroundColor: statusBackground,
      side: BorderSide(color: statusForeground.withValues(alpha: 0.35)),
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: cardColor,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 570;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (compact) ...[
                  orderDetails,
                  Align(alignment: Alignment.centerLeft, child: statusChip),
                ] else
                  Row(
                    children: [
                      Expanded(child: orderDetails),
                      const SizedBox(width: 12),
                      statusChip,
                    ],
                  ),
                if (isBilling && !_expanded) ...[
                  const SizedBox(height: 10),
                  _actionButtons(isBilling),
                ],
                if (_expanded) ...[
                  if (bill.lastPrintStatus?.isNotEmpty == true) ...[
                    const SizedBox(height: 6),
                    Text('Last Print: ${bill.lastPrintStatus}'),
                  ],
                  const Divider(height: 24),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECF3FA),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Items (${bill.items.length})',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF153D69),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...bill.items.map(
                    (item) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            constraints: const BoxConstraints(minWidth: 42),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE3EFFC),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${formatQuantity(item.qty)} ×',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFF153D69),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: Text(item.itemName)),
                          const SizedBox(width: 8),
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
                  _actionButtons(isBilling),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _actionButtons(bool isBilling) {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: _reprintBlue,
              foregroundColor: Colors.white,
              disabledBackgroundColor: _disabledBackground,
              disabledForegroundColor: _disabledForeground,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: isBilling && !widget.printPending
                ? widget.onPrint
                : null,
            icon: widget.printPending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.print),
            label: Text(
              widget.printPending ? 'Sending…' : 'Reprint Bill',
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: _paymentGreen,
              foregroundColor: Colors.white,
              disabledBackgroundColor: _disabledBackground,
              disabledForegroundColor: _disabledForeground,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: isBilling ? widget.onPayment : null,
            icon: const Icon(Icons.point_of_sale),
            label: const Text('Payment'),
          ),
        ),
      ],
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
