import 'package:bcn_restaurant_mobile/features/cashier/domain/cashier_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('billing response parses Sales Order bills', () {
    final response = CashierBillingResponse.fromJson({
      'bills': [
        {
          'sales_order': 'SAL-ORD-2026-00005',
          'customer': 'Table 05',
          'customer_name': 'Table 05',
          'creation': '2026-09-07 15:00:00',
          'net_total': 10000,
          'total_taxes_and_charges': 500,
          'grand_total': 10500,
          'currency': 'MMK',
          'restaurant_status': 'Billing',
          'last_print_status': 'Printed',
          'last_print_job': 'PRINT-JOB-0001',
          'items': [
            {
              'item_code': 'FOOD-001',
              'item_name': 'Sample Food',
              'qty': 1,
              'uom': 'Plate',
              'rate': 10000,
              'amount': 10000,
              'net_amount': 10000,
            },
          ],
          'taxes': [
            {
              'charge_type': 'On Net Total',
              'account_head': 'Service Charge - DMT',
              'description': 'Service Charge',
              'rate': 5,
              'tax_amount': 500,
              'total': 10500,
            },
          ],
        },
      ],
      'modes': [
        {'name': 'Cash', 'default': true},
      ],
    });

    expect(response.bills, hasLength(1));
    final bill = response.bills.single;
    expect(bill.salesOrder, 'SAL-ORD-2026-00005');
    expect(bill.restaurantStatus, 'Billing');
    expect(bill.lastPrintStatus, 'Printed');
    expect(bill.lastPrintJob, 'PRINT-JOB-0001');
    expect(bill.grandTotal, 10500);
    expect(bill.items.single.uom, 'Plate');
    expect(response.modes.single.name, 'Cash');
  });

  test('payment result parses final document identities and duplicate flag', () {
    final result = CashierPaymentResult.fromJson({
      'sales_order': 'SAL-ORD-2026-00005',
      'sales_invoice': 'ACC-SINV-2026-00001',
      'payment_entries': ['ACC-PAY-2026-00001', 'ACC-PAY-2026-00002'],
      'change_amount': 500,
      'duplicate': true,
    });

    expect(result.salesOrder, 'SAL-ORD-2026-00005');
    expect(result.salesInvoice, 'ACC-SINV-2026-00001');
    expect(result.paymentEntries, hasLength(2));
    expect(result.changeAmount, 500);
    expect(result.duplicate, isTrue);
  });
}
