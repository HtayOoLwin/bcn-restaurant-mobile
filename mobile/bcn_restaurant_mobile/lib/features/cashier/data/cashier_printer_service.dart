import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../../core/formatters/amount_format.dart';
import '../domain/cashier_models.dart';

class CashierPrinterService {
  const CashierPrinterService();

  Future<void> printBill({
    required CashierInvoice invoice,
    required CashierPrinterSettings settings,
  }) async {
    if (!settings.isConfigured) {
      throw StateError('Cashier printer is not configured.');
    }

    Socket? socket;
    try {
      socket = await Socket.connect(
        settings.printerIp,
        settings.printerPort,
        timeout: const Duration(seconds: 5),
      );
      socket.add(_buildBill(invoice: invoice, settings: settings));
      await socket.flush();
      await socket.close();
    } on SocketException catch (error) {
      throw StateError(
        'Cannot connect to cashier printer ${settings.printerIp}:${settings.printerPort}. ${error.message}',
      );
    } finally {
      socket?.destroy();
    }
  }

  Uint8List _buildBill({
    required CashierInvoice invoice,
    required CashierPrinterSettings settings,
  }) {
    final width = settings.paperWidth == '58mm' ? 32 : 48;
    final separator = '-' * width;
    final buffer = BytesBuilder();

    void command(List<int> bytes) => buffer.add(bytes);
    void line([String text = '']) => buffer.add(utf8.encode('$text\n'));

    command(const [0x1B, 0x40]);
    command(const [0x1B, 0x61, 0x01]);
    command(const [0x1B, 0x45, 0x01]);
    line('BCN RESTAURANT');
    line('BILL');
    command(const [0x1B, 0x45, 0x00]);
    command(const [0x1B, 0x61, 0x00]);
    line(separator);
    line(invoice.customerName.toUpperCase());
    line('Invoice: ${invoice.name}');
    if (invoice.salesOrders.isNotEmpty) {
      line('Order: ${invoice.salesOrders.join(', ')}');
    }
    if (invoice.creation != null) {
      final created = DateTime.tryParse(invoice.creation!);
      if (created != null) {
        final local = created.toLocal();
        final hh = local.hour.toString().padLeft(2, '0');
        final mm = local.minute.toString().padLeft(2, '0');
        line('Time: $hh:$mm');
      }
    }
    line(separator);

    for (final item in invoice.items) {
      line('${formatQuantity(item.qty)} x ${item.itemName}');
      line('  ${formatAmount(item.amount)}');
    }

    line(separator);
    line('Subtotal: ${formatAmount(invoice.netTotal)}');
    for (final tax in invoice.taxes) {
      final rateText = tax.rate == 0 ? '' : ' ${formatQuantity(tax.rate)}%';
      line('${tax.description}$rateText: ${formatAmount(tax.taxAmount)}');
    }
    command(const [0x1B, 0x45, 0x01]);
    line('Grand Total: ${formatAmount(invoice.grandTotal)} ${invoice.currency}');
    command(const [0x1B, 0x45, 0x00]);
    line(separator);
    command(const [0x1B, 0x61, 0x01]);
    line('Please present this bill for payment.');
    line();
    line();
    command(const [0x1D, 0x56, 0x00]);
    return buffer.takeBytes();
  }
}
