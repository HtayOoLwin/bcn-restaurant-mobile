import '../../../core/formatters/amount_format.dart';
import '../../printing/data/direct_printer_service.dart';
import '../../printing/data/printer_settings_repository.dart';
import '../../printing/domain/printer_config.dart';
import '../../printing/services/esc_pos_raster_builder.dart';
import '../domain/cashier_models.dart';

class CashierPrinterService {
  const CashierPrinterService({
    this.settingsRepository = const PrinterSettingsRepository(),
    this.printerService = const DirectPrinterService(),
    this.ticketBuilder = const EscPosRasterBuilder(),
  });

  final PrinterSettingsRepository settingsRepository;
  final DirectPrinterService printerService;
  final EscPosRasterBuilder ticketBuilder;

  Future<void> printBill({required CashierInvoice invoice}) async {
    final config = await settingsRepository.load();
    if (!config.isConfigured) {
      throw StateError('Printer is not configured on this tablet.');
    }

    final lines = buildTicketLines(invoice: invoice, config: config);
    final bytes = await ticketBuilder.build(config: config, lines: lines);
    final result = await printerService.printBytes(config, bytes);
    if (!result.succeeded) throw StateError(result.message);
  }

  List<TicketLine> buildTicketLines({
    required CashierInvoice invoice,
    required PrinterConfig config,
  }) {
    return <TicketLine>[
      const TicketLine(
        'BCN RESTAURANT',
        bold: true,
        center: true,
        sizeFactor: 1.25,
      ),
      const TicketLine('BILL', bold: true, center: true),
      const TicketLine.dottedRule(),
      TicketLine(invoice.customerName.toUpperCase(), bold: true),
      TicketLine('Invoice: ${invoice.name}'),
      if (invoice.salesOrders.isNotEmpty)
        TicketLine('Order: ${invoice.salesOrders.join(', ')}'),
      if (_creationDate(invoice.creation) case final value?)
        TicketLine('Date: $value'),
      const TicketLine.dottedRule(),
      TicketLine.columns(
        qty: 'QTY',
        description: 'DESCRIPTION',
        rate: 'RATE',
        amount: 'AMOUNT',
        bold: true,
        sizeFactor: 0.72,
      ),
      for (final item in invoice.items)
        TicketLine.columns(
          qty: formatQuantity(item.qty),
          description: item.itemName,
          rate: formatAmount(item.rate),
          amount: formatAmount(item.amount),
        ),
      const TicketLine.dottedRule(),
      TicketLine.columns(
        qty: '',
        description: 'Subtotal',
        rate: '',
        amount: formatAmount(invoice.netTotal),
      ),
      for (final tax in invoice.taxes)
        TicketLine.columns(
          qty: '',
          description:
              '${tax.description}${tax.rate == 0 ? '' : ' ${formatQuantity(tax.rate)}%'}',
          rate: '',
          amount: formatAmount(tax.taxAmount),
        ),
      const TicketLine.dottedRule(),
      TicketLine(
        'GRAND TOTAL: ${formatAmount(invoice.grandTotal)} ${invoice.currency}',
        bold: true,
        right: true,
        sizeFactor: 1.15,
      ),
      if (config.footerRemark.isNotEmpty) ...[
        const TicketLine(''),
        TicketLine(config.footerRemark, center: true),
      ],
    ];
  }

  static String? _creationDate(String? value) {
    final parsed = value == null ? null : DateTime.tryParse(value);
    if (parsed == null) return null;
    final local = parsed.toLocal();
    return '${local.day.toString().padLeft(2, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.year.toString().padLeft(4, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}
