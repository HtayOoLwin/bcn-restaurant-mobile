import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/formatters/amount_format.dart';
import '../../../core/formatters/amount_input_formatter.dart';
import '../../../core/search/order_search.dart';
import '../../../core/widgets/operational_refresh_indicator.dart';
import '../../../core/widgets/order_search_field.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../kitchen/presentation/kitchen_notification_badge.dart';
import '../../waiter/presentation/waiter_tables_screen.dart';
import '../data/cashier_printer_service.dart';
import '../data/cashier_repository.dart';
import '../domain/cashier_models.dart';

final cashierRepositoryProvider = Provider<CashierRepository>(
  (ref) => CashierRepository(ref.watch(apiClientProvider)),
);

final cashierPrinterServiceProvider = Provider<CashierPrinterService>(
  (ref) => const CashierPrinterService(),
);

final cashierBillingProvider = FutureProvider<CashierBillingResponse>(
  (ref) => ref.watch(cashierRepositoryProvider).getBilling(),
);

class CashierScreen extends ConsumerStatefulWidget {
  const CashierScreen({super.key});

  @override
  ConsumerState<CashierScreen> createState() => _CashierScreenState();
}

class _CashierScreenState extends ConsumerState<CashierScreen> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final bootstrap = ref.watch(authControllerProvider).asData?.value.bootstrap;
    final billing = ref.watch(cashierBillingProvider);
    final kitchenNewOrderCount =
        ref.watch(kitchenNewOrderCountProvider).asData?.value ?? 0;

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
          if (bootstrap?.permissions.kitchen == true)
            IconButton(
              tooltip: 'Kitchen',
              onPressed: () => context.go('/kitchen'),
              icon: kitchenNewOrderCount > 0
                  ? Badge.count(
                      count: kitchenNewOrderCount,
                      child: const Icon(Icons.soup_kitchen),
                    )
                  : const Icon(Icons.soup_kitchen),
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
                final filteredInvoices = data.invoices
                    .where(
                      (invoice) => matchesOrderSearch(
                        queryText: _searchQuery,
                        tableName: invoice.customerName,
                        orderNumbers: invoice.salesOrders,
                      ),
                    )
                    .toList();
                return RefreshIndicator(
                  onRefresh: () => ref.refresh(cashierBillingProvider.future),
                  child: data.invoices.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 180),
                            Center(child: Text('No bills ready for payment.')),
                          ],
                        )
                      : filteredInvoices.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 180),
                            Center(child: Text('No bills match your search.')),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: filteredInvoices.length,
                          itemBuilder: (context, index) {
                            final invoice = filteredInvoices[index];
                            return _InvoiceCard(
                              invoice: invoice,
                              onPrint: () => _printInvoice(
                                context: context,
                                invoice: invoice,
                              ),
                              onPayment: () => _openPaymentSheet(
                                context: context,
                                ref: ref,
                                billing: data,
                                invoice: invoice,
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

  Future<void> _printInvoice({
    required BuildContext context,
    required CashierInvoice invoice,
  }) async {
    try {
      await ref.read(cashierPrinterServiceProvider).printBill(invoice: invoice);
      await ref
          .read(cashierRepositoryProvider)
          .recordBillPrint(invoiceName: invoice.name);
      ref.invalidate(cashierBillingProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Bill printed.')));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _openPaymentSheet({
    required BuildContext context,
    required WidgetRef ref,
    required CashierBillingResponse billing,
    required CashierInvoice invoice,
  }) async {
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
    final fullAmountText = formatAmount(invoice.outstandingAmount);

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
          secondaryMode == null) {
        return;
      }
      if (changedMode != secondaryMode.name) {
        return;
      }

      final secondAmount = _parseTender(controllers[secondaryMode.name]?.text);
      final balance = (invoice.outstandingAmount - secondAmount)
          .clamp(0, double.infinity)
          .toDouble();
      setControllerAmount(controllers[primaryMode.name], balance);
    }

    if (selectedPaymentType.isNotEmpty) {
      setPaymentType(selectedPaymentType);
    }

    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (sheetContext) => StatefulBuilder(
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

            final remaining = totalTendered < invoice.outstandingAmount
                ? invoice.outstandingAmount - totalTendered
                : 0.0;
            final change = totalTendered > invoice.outstandingAmount
                ? totalTendered - invoice.outstandingAmount
                : 0.0;
            final nonCashOver =
                nonCashTotal > invoice.outstandingAmount + 0.0001;
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
                        '${invoice.customerName} · ${invoice.name}',
                        style: Theme.of(sheetContext).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Amount Due: ${formatMoney(invoice.outstandingAmount, invoice.currency)}',
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
                              suffixText: invoice.currency,
                              border: const OutlineInputBorder(),
                            ),
                            onChanged: (_) =>
                                setSheetState(() => onTenderChanged(mode.name)),
                          ),
                        ),
                      ),
                      _AmountSummaryRow(
                        label: 'Total Tendered',
                        value: formatMoney(totalTendered, invoice.currency),
                      ),
                      _AmountSummaryRow(
                        label: 'Remaining',
                        value: formatMoney(remaining, invoice.currency),
                      ),
                      _AmountSummaryRow(
                        label: 'Change',
                        value: formatMoney(change, invoice.currency),
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
                                        invoiceName: invoice.name,
                                        payments: tenders,
                                      );
                                  ref.invalidate(cashierBillingProvider);
                                  ref.invalidate(tablesProvider('dine_in'));
                                  ref.invalidate(tablesProvider('takeaway'));
                                  if (sheetContext.mounted)
                                    Navigator.of(sheetContext).pop();
                                  if (context.mounted) {
                                    final entries =
                                        result.paymentEntries.isNotEmpty
                                        ? result.paymentEntries.join(', ')
                                        : (result.paymentEntry ?? '');
                                    final changeText = result.changeAmount > 0
                                        ? ' · Change ${formatMoney(result.changeAmount, invoice.currency)}'
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
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
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
      );
    } finally {
      for (final controller in controllers.values) {
        controller.dispose();
      }
    }
  }
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

class _InvoiceCard extends StatelessWidget {
  const _InvoiceCard({
    required this.invoice,
    required this.onPrint,
    required this.onPayment,
  });

  final CashierInvoice invoice;
  final VoidCallback onPrint;
  final VoidCallback onPayment;

  @override
  Widget build(BuildContext context) {
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
                        invoice.customerName,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        invoice.name,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (invoice.salesOrders.isNotEmpty)
                        Text(
                          "Order: ${invoice.salesOrders.join(', ')}",
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                Chip(label: Text(invoice.paymentStatus)),
              ],
            ),
            const Divider(height: 24),
            ...invoice.items.map(
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
                    Text(formatMoney(item.amount, invoice.currency)),
                  ],
                ),
              ),
            ),
            const Divider(height: 24),
            _AmountSummaryRow(
              label: 'Subtotal',
              value: formatMoney(invoice.netTotal, invoice.currency),
            ),
            ...invoice.taxes.map(
              (tax) => _AmountSummaryRow(
                label: tax.rate == 0
                    ? tax.description
                    : '${tax.description} ${formatQuantity(tax.rate)}%',
                value: formatMoney(tax.taxAmount, invoice.currency),
              ),
            ),
            const SizedBox(height: 4),
            _AmountSummaryRow(
              label: 'Grand Total',
              value: formatMoney(invoice.grandTotal, invoice.currency),
              emphasize: true,
            ),
            if (invoice.docstatus == 1 &&
                (invoice.outstandingAmount - invoice.grandTotal).abs() > 0.0001)
              _AmountSummaryRow(
                label: 'Outstanding',
                value: formatMoney(invoice.outstandingAmount, invoice.currency),
                emphasize: true,
              ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                FilledButton.icon(
                  onPressed: onPrint,
                  icon: const Icon(Icons.print),
                  label: Text(
                    invoice.billPrinted ? 'Reprint Bill' : 'Print Bill',
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: onPayment,
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
