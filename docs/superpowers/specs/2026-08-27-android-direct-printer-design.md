# Android Direct Printer Design

## Scope

Add manual direct printing to the Android Flutter client without using the
`local_printers` Frappe app, Windows middleware, or a Windows gateway.

The first release supports:

- Android tablets only.
- Bluetooth ESC/POS printers.
- Wi-Fi/LAN ESC/POS printers over TCP, with port 9100 as the default.
- One locally configured printer per tablet.
- 58 mm and 80 mm paper widths.
- Manual Kitchen Ticket, Cancel Order ticket, and Cashier Bill printing.
- Test Print from Printer Settings.

USB, Windows desktop, automatic printing, and item-group printer routing are
outside this release.

## Confirmed Business Flow

### Kitchen order

1. The waiter explicitly taps `Print Kitchen Ticket`.
2. The server calculates ordered quantity minus successfully printed quantity
   for every active Sales Order item.
3. Only new or increased quantities are included in the print request.
4. The Android tablet prints the ticket through its saved printer.
5. Printed quantity is updated only after the tablet reports a successful
   connection and complete data write.
6. Failed jobs remain retryable and do not update printed quantity.

### Cancel order

1. The waiter uses the `Cancel Order` action and chooses the item, quantity,
   and cancellation reason.
2. The business cancellation remains valid even if printing fails.
3. If the cancelled quantity was previously sent to the kitchen, a manual
   `CANCEL ORDER` ticket is created for that quantity.
4. A failed cancellation ticket remains available for retry.

### Cashier bill and payment

1. When all applicable items are Served, the existing workflow creates a Draft
   Sales Invoice.
2. The cashier may tap `Print Bill` to print that Draft Sales Invoice.
3. Printing is optional. A skipped or failed print never blocks payment.
4. On `Payment Confirm`, the system creates and submits the Delivery Note and
   submits the Draft Sales Invoice.

## Printer Settings

Printer configuration is stored locally on each Android tablet because each
tablet can use a different physical printer.

The settings page follows the existing BCN Restaurant mobile visual language
and the approved reference layout. It contains:

- Connection selector: Bluetooth or Wi-Fi.
- Bluetooth printer discovery and selected device name/MAC address.
- Wi-Fi printer IP address, port, and connection timeout.
- Paper width: 58 mm or 80 mm.
- Adjustable receipt font size with a live sample.
- Footer Remark text.
- Auto-cut enabled/disabled.
- Printer enabled/disabled.
- Test Print and Save Printer Setup actions.

USB is not displayed. The bottom actions remain easy to access on a scrollable
screen. Save is allowed without a successful Test Print so configuration can
be prepared before the printer is available.

## Flutter Architecture

Printing is isolated under `lib/features/printing/`:

- `domain`: printer device, configuration, job, result, and adapter contract.
- `data`: Bluetooth and network adapters plus local configuration storage.
- `services`: ESC/POS encoding and ticket builders.
- `presentation`: settings, discovery, test, and print-result UI.

Both transport implementations conform to one printer adapter interface. The
Kitchen, Cancel Order, and Cashier features depend on the interface rather than
Bluetooth- or network-specific code.

## Print Result Semantics

Most generic ESC/POS printers cannot confirm that paper physically exited the
printer. In this release, `Success` means:

- a connection to the configured printer was established;
- the complete ESC/POS payload was written without an exception; and
- no transport-level error was reported.

Model-specific paper-out, cover-open, or physical completion checks can be
added later when a selected printer supports realtime status commands.

Jobs use these states:

- `Queued`
- `Processing`
- `Success`
- `Failed`

Failed jobs keep an error message and attempt count and can be retried. A unique
job identifier prevents a successful Kitchen or Cancel payload from updating
the same tracked quantity twice.

## Ticket Layouts

### Kitchen Ticket

Displays:

- `KITCHEN ORDER`, or `KITCHEN ORDER - ADD` for increased quantity.
- Sales Order number, table, waiter, guest count when available, and time.
- Only unprinted item quantity, item name, modifiers, and kitchen notes.
- General kitchen/order note when present.
- Print time and job identifier.

It does not display rate, discount, tax, totals, or payment information.

### Cancel Order Ticket

Displays:

- A prominent `CANCEL ORDER` heading.
- Sales Order number, table, waiter, and cancellation time.
- Item, cancelled quantity, modifiers, and cancellation reason.
- Original printed quantity, cancelled quantity, and remaining active quantity.
- Cancelling user and job identifier.

The layout uses strong separators and double-size or reverse text when the
printer supports it so it cannot be confused with a new kitchen ticket.

### Cashier Bill

The source is the existing Draft Sales Invoice. It displays:

- Restaurant name and configured contact details.
- Invoice number, table, date/time, cashier, and non-cash customer when present.
- Item quantity, item name, rate where paper width permits, and line amount.
- Subtotal, discount, service charge, tax, grand total, and currency.
- The exact locally configured Printer Settings `Footer Remark` at the bottom.

It does not display `PAYMENT PENDING`, paid amount, payment mode, change amount,
or `PAID` because the source invoice is still a draft printed before payment.

## Paper Width and Myanmar Text

The ticket builders use width-aware column definitions. A 58 mm layout is
compact and wraps long item names; an 80 mm layout can include a separate rate
column and wider item names.

When the printer code page cannot render Myanmar Unicode correctly, Myanmar
sections are rasterized to an image before being embedded in the ESC/POS
payload. Plain supported text remains native ESC/POS text for speed.

## Error Handling

- Missing printer setup: show a direct link to Printer Settings.
- Bluetooth permission denied: explain the required permission and allow retry.
- Bluetooth device unavailable: keep the job failed and retryable.
- Invalid/unreachable Wi-Fi address: show connection failure without updating
  printed quantity.
- Partial or failed write: mark the job failed; do not update printed quantity.
- No new kitchen quantities: do not create a job and inform the waiter.
- Duplicate request: reuse or reject the existing job identifier.
- Print failure: never roll back an order cancellation or block payment.

## Verification

Tests must cover:

- New and increased kitchen quantity calculation.
- Successfully printed quantity changing only on Success.
- Cancelled quantity and Cancel ticket retry behavior.
- Duplicate acknowledgement protection.
- Bluetooth and Wi-Fi adapter selection.
- 58 mm and 80 mm ticket formatting.
- Dynamic Footer Remark on the Cashier Bill.
- Cashier payment proceeding without a print or after a failed print.
- Printer Settings persistence and Test Print behavior.

Real Android-device checks must cover Bluetooth permissions, Bluetooth
discovery/printing, Wi-Fi printing, Myanmar raster output, disconnect/retry,
and paper width differences.
