import '../../printing/data/direct_printer_service.dart';
import '../../printing/data/printer_settings_repository.dart';
import '../../printing/services/esc_pos_raster_builder.dart';
import '../domain/kitchen_models.dart';

class KitchenPrinterService {
  const KitchenPrinterService({
    this.settingsRepository = const PrinterSettingsRepository(),
    this.printerService = const DirectPrinterService(),
    this.ticketBuilder = const EscPosRasterBuilder(),
  });

  final PrinterSettingsRepository settingsRepository;
  final DirectPrinterService printerService;
  final EscPosRasterBuilder ticketBuilder;

  Future<void> printOrder({
    required KitchenOrder order,
    required String counterName,
    required List<KitchenOrderItem> items,
    required bool isReprint,
  }) async {
    if (items.isEmpty) throw StateError('There are no kitchen items to print.');
    final config = await settingsRepository.load();
    if (!config.isConfigured) {
      throw StateError('Printer is not configured on this tablet.');
    }

    final lines = <TicketLine>[
      TicketLine(
        counterName.toUpperCase().contains('KITCHEN')
            ? counterName.toUpperCase()
            : '${counterName.toUpperCase()} KITCHEN',
        bold: true,
        center: true,
        sizeFactor: 1.25,
      ),
      TicketLine(isReprint ? 'REPRINT' : 'NEW ORDER', bold: true, center: true),
      const TicketLine.dottedRule(),
      TicketLine(order.customer.toUpperCase(), bold: true),
      TicketLine('Order: ${order.name}'),
      if (order.creation != null) TicketLine('Time: ${_time(order.creation!)}'),
      const TicketLine.dottedRule(),
      for (final item in items) ...[
        TicketLine(
          '${_qty(item.qty)} x ${item.itemName}',
          bold: true,
          sizeFactor: 1.1,
        ),
        if (item.kitchenNote?.trim().isNotEmpty == true)
          TicketLine(
            '  *** ${item.kitchenNote!.trim().toUpperCase()} ***',
            bold: true,
          ),
      ],
      const TicketLine.dottedRule(),
      TicketLine(isReprint ? 'REPRINT' : 'NEW ORDER', bold: true, center: true),
    ];
    final bytes = await ticketBuilder.build(config: config, lines: lines);
    final result = await printerService.printBytes(config, bytes);
    if (!result.succeeded) throw StateError(result.message);
  }

  static String _time(DateTime value) {
    final local = value.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  static String _qty(double qty) =>
      qty == qty.roundToDouble() ? qty.toInt().toString() : qty.toString();
}
