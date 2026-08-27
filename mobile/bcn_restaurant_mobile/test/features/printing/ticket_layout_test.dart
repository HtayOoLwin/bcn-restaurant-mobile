import 'package:bcn_restaurant_mobile/features/cashier/data/cashier_printer_service.dart';
import 'package:bcn_restaurant_mobile/features/cashier/domain/cashier_models.dart';
import 'package:bcn_restaurant_mobile/features/kitchen/data/kitchen_printer_service.dart';
import 'package:bcn_restaurant_mobile/features/kitchen/domain/kitchen_models.dart';
import 'package:bcn_restaurant_mobile/features/printing/domain/printer_config.dart';
import 'package:bcn_restaurant_mobile/features/printing/services/esc_pos_raster_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'cashier bill has compact columns without rules below header or total',
    () {
      final invoice = CashierInvoice.fromJson({
        'name': 'ACC-SINV-0001',
        'customer': 'Table 01',
        'customer_name': 'Table 01',
        'creation': '2026-08-27 16:18:00',
        'net_total': 3500,
        'grand_total': 3500,
        'currency': 'MMK',
        'items': [
          {
            'item_code': 'BEER',
            'item_name': 'Beer',
            'qty': 1,
            'rate': 3500,
            'amount': 3500,
          },
        ],
      });

      final lines = const CashierPrinterService().buildTicketLines(
        invoice: invoice,
        config: const PrinterConfig.defaults(),
      );
      final headerIndex = lines.indexWhere(
        (line) => line.columns?.description == 'DESCRIPTION',
      );
      final totalIndex = lines.indexWhere(
        (line) => line.text.startsWith('GRAND TOTAL'),
      );

      expect(headerIndex, greaterThan(-1));
      expect(lines[headerIndex].columns?.qty, 'QTY');
      expect(lines[headerIndex].columns?.rate, 'RATE');
      expect(lines[headerIndex].columns?.amount, 'AMOUNT');
      expect(lines[headerIndex + 1].isDottedRule, isFalse);
      expect(totalIndex, greaterThan(-1));
      expect(
        totalIndex == lines.length - 1 || !lines[totalIndex + 1].isDottedRule,
        isTrue,
      );
      expect(lines.where((line) => line.isDottedRule), isNotEmpty);
      expect(
        lines.any((line) => line.text == 'Date: 27-08-2026 16:18'),
        isTrue,
      );
    },
  );

  test('kitchen ticket labels its date and time as Date', () {
    final lines = const KitchenPrinterService().buildTicketLines(
      order: KitchenOrder(
        name: 'SAL-ORD-0001',
        customer: 'Table 01',
        preparationSummary: 'New',
        items: const [],
        creation: DateTime(2026, 8, 27, 16, 18),
      ),
      counterName: 'Kitchen',
      items: const [],
      isReprint: false,
    );

    expect(lines.any((line) => line.text == 'Date: 27-08-2026 16:18'), isTrue);
  });

  test('ticket row factories describe full-width rules and amount columns', () {
    const rule = TicketLine.dottedRule();
    final row = TicketLine.columns(
      qty: '2',
      description: 'Tea',
      rate: '1,000',
      amount: '2,000',
    );

    expect(rule.isDottedRule, isTrue);
    expect(row.columns?.amount, '2,000');
  });
}
