import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../domain/kitchen_models.dart';

class KitchenPrinterService {
  const KitchenPrinterService();

  Future<void> printOrder({
    required KitchenOrder order,
    required String counterName,
    required KitchenPrinterSettings settings,
    required List<KitchenOrderItem> items,
    required bool isReprint,
  }) async {
    if (!settings.isConfigured) {
      throw StateError('Printer is not configured for $counterName.');
    }
    if (items.isEmpty) {
      throw StateError('There are no kitchen items to print.');
    }

    Socket? socket;
    try {
      socket = await Socket.connect(
        settings.printerIp,
        settings.printerPort,
        timeout: const Duration(seconds: 5),
      );
      socket.add(_buildTicket(
        order: order,
        counterName: counterName,
        settings: settings,
        items: items,
        isReprint: isReprint,
      ));
      await socket.flush();
      await socket.close();
    } on SocketException catch (error) {
      throw StateError(
        'Cannot connect to printer ${settings.printerIp}:${settings.printerPort}. ${error.message}',
      );
    } finally {
      if (socket != null) {
        socket.destroy();
      }
    }
  }

  Uint8List _buildTicket({
    required KitchenOrder order,
    required String counterName,
    required KitchenPrinterSettings settings,
    required List<KitchenOrderItem> items,
    required bool isReprint,
  }) {
    final width = settings.paperWidth == '58mm' ? 32 : 48;
    final separator = '-' * width;
    final buffer = BytesBuilder();

    void command(List<int> bytes) => buffer.add(bytes);
    void line([String text = '']) => buffer.add(utf8.encode('$text\n'));

    command(const [0x1B, 0x40]); // ESC @ - initialize
    command(const [0x1B, 0x61, 0x01]); // center
    command(const [0x1B, 0x45, 0x01]); // bold on
    line(counterName.toUpperCase().contains('KITCHEN')
        ? counterName.toUpperCase()
        : '${counterName.toUpperCase()} KITCHEN');
    command(const [0x1B, 0x45, 0x00]); // bold off
    if (isReprint) {
      command(const [0x1B, 0x45, 0x01]);
      line('***** REPRINT *****');
      command(const [0x1B, 0x45, 0x00]);
    }
    command(const [0x1B, 0x61, 0x00]); // left
    line(separator);
    command(const [0x1B, 0x45, 0x01]);
    line(order.customer.toUpperCase());
    command(const [0x1B, 0x45, 0x00]);
    line('Order: ${order.name}');
    if (order.creation != null) {
      final created = order.creation!.toLocal();
      final hh = created.hour.toString().padLeft(2, '0');
      final mm = created.minute.toString().padLeft(2, '0');
      line('Time : $hh:$mm');
    }
    line(separator);
    for (final item in items) {
      command(const [0x1B, 0x45, 0x01]);
      line('${_qty(item.qty)} x ${item.itemName}');
      command(const [0x1B, 0x45, 0x00]);
      if (item.kitchenNote?.trim().isNotEmpty == true) {
        line('  *** ${item.kitchenNote!.trim().toUpperCase()} ***');
      }
      line();
    }
    line(separator);
    command(const [0x1B, 0x61, 0x01]);
    line(isReprint ? 'REPRINT' : 'NEW ORDER');
    line();
    line();
    command(const [0x1D, 0x56, 0x00]); // cut
    return buffer.takeBytes();
  }

  String _qty(double qty) => qty == qty.roundToDouble() ? qty.toInt().toString() : qty.toString();
}
