import '../../../core/formatters/amount_format.dart';
import '../../printing/data/direct_printer_service.dart';
import '../../printing/data/printer_settings_repository.dart';
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

    final lines = <TicketLine>[
      const TicketLine(
        'BCN RESTAURANT',
        bold: true,
        center: true,
        sizeFactor: 1.35,
      ),
      const TicketLine('BILL', bold: true, center: true),
      const TicketLine('--------------------------------'),
      TicketLine(invoice.customerName.toUpperCase(), bold: true),
      TicketLine('Invoice: ${invoice.name}'),
      if (invoice.salesOrders.isNotEmpty)
        TicketLine('Order: ${invoice.salesOrders.join(', ')}'),
      if (_creationTime(invoice.creation) case final value?)
        TicketLine('Time: $value'),
      const TicketLine('--------------------------------'),
      for (final item in invoice.items) ...[
        TicketLine('${formatQuantity(item.qty)} x ${item.itemName}'),
        TicketLine(
          '  ${formatAmount(item.rate)} x ${formatQuantity(item.qty)} = '
          '${formatAmount(item.amount)}',
        ),
      ],
      const TicketLine('--------------------------------'),
      TicketLine('Subtotal: ${formatAmount(invoice.netTotal)}'),
      for (final tax in invoice.taxes)
        TicketLine(
          '${tax.description}${tax.rate == 0 ? '' : ' ${formatQuantity(tax.rate)}%'}: '
          '${formatAmount(tax.taxAmount)}',
        ),
      TicketLine(
        'Grand Total: ${formatAmount(invoice.grandTotal)} ${invoice.currency}',
        bold: true,
        sizeFactor: 1.15,
      ),
      if (config.footerRemark.isNotEmpty) ...[
        const TicketLine('--------------------------------'),
        TicketLine(config.footerRemark, center: true),
      ],
    ];
    final bytes = await ticketBuilder.build(config: config, lines: lines);
    final result = await printerService.printBytes(config, bytes);
    if (!result.succeeded) throw StateError(result.message);
  }

  static String? _creationTime(String? value) {
    final parsed = value == null ? null : DateTime.tryParse(value);
    if (parsed == null) return null;
    final local = parsed.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}
