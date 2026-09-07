# Cashier Draft Sales Order Billing Design

Date: 2026-09-07
Target branch: `bcn-restaurant-mobile-without-kitchen-monitor`
Target site: `https://ourcity.s.frappe.cloud`

## Summary

The restaurant mobile flow keeps one active Draft Sales Order per table visit. Waiters may add items while the order is `Open`. Cashier work starts from that Draft Sales Order instead of creating a Sales Invoice early.

The approved cashier flow is:

```text
Open Draft Sales Order
-> Cashier views bill
-> Print Bill or start Payment
-> Restaurant Status = Billing
-> Waiter edits are blocked
-> Payment confirm
-> Submit Sales Order
-> Create and submit Sales Invoice with Update Stock = 1
-> Create and submit Payment Entry/Entries
-> Restaurant Status = Closed
-> Table becomes Available
```

The bill printed before payment is rendered from the Draft Sales Order. A Sales Invoice is created only when payment is confirmed.

## Goals

- Preserve the one-Draft-Sales-Order-per-table restaurant flow.
- Allow cashier bill preview and printing before payment.
- Freeze the order when printing or payment begins.
- Prevent waiter changes after the bill is frozen.
- Create accounting and stock documents only at payment finalization.
- Use Sales Invoice `update_stock = 1`; do not create a Delivery Note in this flow.
- Support Cash, Kpay, and split payment.
- Prevent duplicate Sales Invoices and Payment Entries when a payment request is retried.
- Keep printed bill totals and final Sales Invoice totals consistent.
- Return the table to Available only after successful payment finalization.
- Continue using the Windows local printer client rather than Android/Bluetooth printing or Kitchen Monitor UI.

## Non-goals

- Do not merge this branch into `main` as part of this work.
- Do not reintroduce Restaurant Table Session.
- Do not create a Delivery Note for cashier checkout.
- Do not submit the Sales Order from the waiter order API.
- Do not install the BCN Restaurant custom app on OurCity as a requirement for mobile API aliases.
- Do not use ERPNext Workflow as the primary state engine for restaurant order printing or payment.
- Kitchen delta printing is a separate phase; this design covers cashier bill printing and checkout.

## Existing Restaurant State

The active restaurant order is a `Sales Order` with `docstatus = 0` and one of these values in `custom_restaurant_status`:

- `Open`
- `Billing`
- `Closed`

The active waiter flow already treats a Draft Sales Order as the table visit. `bcn_mobile_tables` derives table status from Draft Sales Orders:

```text
No Open/Billing Draft SO -> Available
Open Draft SO            -> Occupied
Billing Draft SO         -> Billing
```

`bcn_mobile_create_order` must reject waiter additions when the table has a Billing Draft Sales Order.

## State Machine

### Open

- Cashier GET may display the bill without changing state.
- Waiter may continue adding items.
- `Print Bill` changes the order to `Billing` before the print request is accepted.
- Starting Payment also changes the order to `Billing` before finalization begins.

### Billing

- Waiter changes are blocked.
- Cashier may reprint the bill.
- Cashier may complete payment.
- Printer failure after the print request has been accepted does not reopen the order.

### Closed

- The order is no longer returned by the active cashier list.
- The table is Available because there is no active Open/Billing Draft Sales Order.
- Closed is reached only after Sales Order submission, Sales Invoice submission, and required Payment Entry submission succeed.

## API Design

### `bcn_cashier_billing` — GET

Returns active Draft Sales Orders in `Open` or `Billing` state.

Response shape:

```json
{
  "bills": [
    {
      "sales_order": "SAL-ORD-2026-00001",
      "customer": "Table 01",
      "customer_name": "Table 01",
      "creation": "2026-09-07 10:00:00",
      "net_total": 10000,
      "total_taxes_and_charges": 500,
      "grand_total": 10500,
      "currency": "MMK",
      "restaurant_status": "Open",
      "items": [],
      "taxes": [],
      "bill_printed": false,
      "bill_printed_at": null,
      "bill_printed_by": null
    }
  ],
  "modes": [],
  "printer_settings": {}
}
```

The response is Sales Order based. It does not require a Sales Invoice to exist.

### `bcn_cashier_print_bill` — POST

Input:

```json
{
  "sales_order": "SAL-ORD-2026-00001"
}
```

Rules:

1. Require an authenticated cashier/manager role.
2. Load and lock the Draft Sales Order.
3. Reject cancelled, submitted, Closed, unknown, or unrelated orders.
4. If status is `Open`, set `custom_restaurant_status = "Billing"`.
5. If status is already `Billing`, treat the request as a reprint.
6. Render the cashier bill from the Draft Sales Order.
7. Publish a Windows print event.
8. Return an accepted print result.

A failure before the print event is accepted rolls back the Open -> Billing transition. A failure in the Windows printer after event acceptance leaves the order in Billing.

### `bcn_cashier_billing` — POST `action=Pay`

Input:

```json
{
  "action": "Pay",
  "sales_order": "SAL-ORD-2026-00001",
  "payments": [
    {"mode_of_payment": "Cash", "amount": 5000},
    {"mode_of_payment": "Kpay", "amount": 5500}
  ]
}
```

Rules:

1. Require an authenticated cashier/manager role.
2. Lock the Sales Order and validate it is active.
3. Move `Open` to `Billing` if payment started without a prior bill print.
4. Validate tenders before creating accounting documents.
5. Submit the Sales Order.
6. Create one Sales Invoice from the Sales Order with `update_stock = 1`.
7. Submit the Sales Invoice.
8. Create one submitted Payment Entry per positive tender.
9. Verify the invoice is fully settled except for permitted cash change handling.
10. Mark the Sales Order `custom_restaurant_status = "Closed"`.
11. Return the Sales Invoice, Payment Entry names, and change amount.

## Cashier Bill Model

The Flutter cashier feature changes from an invoice-first model to an active Sales Order bill model.

Primary bill fields:

```text
salesOrder
customer
customerName
creation
netTotal
totalTaxesAndCharges
grandTotal
currency
restaurantStatus
items
taxes
billPrinted
billPrintedAt
billPrintedBy
```

The current mobile payment tender model remains suitable for Cash, Kpay, and split payment.

## UI Behavior

### Open bill card

- Status chip: `Open`
- Actions: `Print Bill`, `Payment`
- Merely opening or refreshing the cashier screen does not freeze the order.

### Billing bill card

- Status chip: `Billing`
- Actions: `Reprint Bill`, `Payment`
- Waiter additions are rejected by the server.

### Payment success

- Cashier bill card disappears from the active list.
- Cashier provider refreshes.
- Dine In and Takeaway table providers refresh.
- The table becomes Available.

## Print Source and Windows Print Transport

The cashier bill is rendered from the Draft Sales Order, not from a Sales Invoice.

The Windows client already listens for `document_print_event` and accepts a payload containing a list of jobs with a base64 PDF, printer name, print format, and document identifiers. The new cashier print API will use that existing event contract so the Windows application does not need Android/Bluetooth printing support.

Expected event shape:

```json
{
  "doctype": "Sales Order",
  "document_name": "SAL-ORD-2026-00001",
  "method": "manual",
  "jobs": [
    {
      "doctype": "Sales Order",
      "document_name": "SAL-ORD-2026-00001",
      "invoice_name": "SAL-ORD-2026-00001",
      "printer": "<configured cashier printer>",
      "is_cashier": true,
      "print_format": "<configured cashier print format>",
      "pdf_base64": "<rendered PDF>"
    }
  ]
}
```

The printer name and print format are deployment configuration, not restaurant-order state. Missing or ambiguous cashier printer configuration is an error and must not silently select an arbitrary printer.

OurCity continues to expose mobile endpoints through Frappe Server Script API aliases. The implementation must use APIs available inside Server Script safe execution. It must not depend on importing `bcn_restaurant` or `local_printers` Python modules on OurCity. The implementation plan must verify the safe-exec PDF-render/base64/realtime path before the production print endpoint is finalized.

## Payment Validation

The server validates all tender amounts before submitting the Sales Order.

Rules:

- Ignore or reject zero/negative tender rows rather than creating zero-value Payment Entries.
- At least one positive tender is required.
- Non-cash tender total may not exceed the invoice amount.
- Cash may exceed the remaining amount; the excess is returned as `change_amount`.
- Overpayment is valid only when the excess is represented by Cash.
- The total usable tender must cover the amount due.

For split payment, each positive tender creates its own Payment Entry after Sales Invoice submission.

## Stock Handling

The checkout path uses:

```text
Sales Invoice
update_stock = 1
```

No Delivery Note is created. Stock reduction happens when the Sales Invoice is submitted.

The generated Sales Invoice must preserve Sales Order item references so ERPNext order/invoice linkage remains traceable.

## Tax and Service Charge Consistency

The Draft Sales Order is the source of the bill that the customer sees before payment. Therefore tax/service-charge configuration must be applied before the order is printed.

The DMT POS Profile and its configured selling/tax setup are the source of truth for restaurant checkout.

Required consistency rule:

```text
Billing Sales Order Grand Total == Final Sales Invoice Grand Total
```

The same applies to Net Total and Total Taxes and Charges within normal currency rounding tolerance.

If the generated Sales Invoice total differs from the frozen Billing Sales Order total, payment finalization stops and the transaction rolls back. The server does not silently accept a changed amount.

## Idempotency and Concurrency

### Payment

Payment finalization must be retry-safe.

Before creating a new Sales Invoice, the server checks whether the Sales Order has already been finalized. If the request is retried after a timeout and the final Sales Invoice/Payment Entries already exist, the API returns the existing result rather than creating duplicates.

The Sales Order must be locked during finalization so two cashier devices cannot finalize the same table simultaneously.

A deterministic linkage from Sales Order to final Sales Invoice is required. Existing ERPNext Sales Order references on Sales Invoice Items are used for traceability; the implementation also records enough finalized-document state to resolve a retry without guessing.

### Print

An Open -> Billing transition occurs once. Further print requests while Billing are reprints and do not alter financial state.

## Transaction Boundaries

Payment finalization is one server request and one database transaction from validation through Closed state.

If any of these fail:

- Sales Order submit
- Sales Invoice creation
- Sales Invoice submit
- Payment Entry creation/submission
- amount consistency validation

then the request returns an error and the database transaction is rolled back. The system must not leave a half-finalized order as the normal result of a failed request.

The print path is separate from payment. A print event accepted by the server may still fail later on the Windows machine; that operational failure does not reopen the bill.

## Error Handling

User-facing failures should identify the actionable condition without exposing stack traces.

Examples:

- Table/order no longer exists.
- Order is already submitted/cancelled/closed.
- More than one active Draft Sales Order exists for the same table.
- Order is Billing and waiter tries to add more items.
- No cashier printer configuration exists.
- Payment mode is invalid or unavailable.
- Tender total is insufficient.
- Non-cash overpayment is not allowed.
- Sales Invoice amount does not match the frozen bill.
- Stock validation prevents Sales Invoice submission.

## Files and Components Expected to Change

Server-script mirror and docs:

```text
server_scripts/mobile/cashier_billing.py
server_scripts/mobile/cashier_print_bill.py
server_scripts/mobile/create_order.py        # only if final lock/idempotency integration needs adjustment
docs/server-script-mobile.md
```

Flutter:

```text
mobile/bcn_restaurant_mobile/lib/features/cashier/data/cashier_repository.dart
mobile/bcn_restaurant_mobile/lib/features/cashier/domain/cashier_models.dart
mobile/bcn_restaurant_mobile/lib/features/cashier/presentation/cashier_screen.dart
mobile/bcn_restaurant_mobile/lib/features/printing/data/windows_print_repository.dart
```

Tests:

```text
tests/test_ourcity_server_script_contract.py
mobile/bcn_restaurant_mobile/test/... cashier/printing tests
```

The implementation may add focused helper/test files, but unrelated refactoring is out of scope.

## Testing Strategy

### Server-script contract tests

Verify source-controlled mirrors enforce:

- active list uses Open/Billing Draft Sales Orders;
- waiter order is blocked while Billing;
- print changes Open to Billing and supports Billing reprint;
- payment uses the Sales Order identifier rather than invoice-first input;
- final Sales Invoice uses Update Stock;
- payment completion marks Closed;
- amount mismatch blocks completion;
- retry logic prevents duplicate finalization.

### Flutter tests

Verify:

- Sales Order bill JSON parsing;
- Open card shows Print Bill + Payment;
- Billing card shows Reprint Bill + Payment;
- payment request sends Sales Order and tender list;
- successful payment refreshes cashier and table providers;
- closed bill disappears after refresh.

### OurCity live smoke test

Use a controlled table/order:

```text
Waiter order
-> Table Occupied
-> Cashier sees Open Draft SO
-> Print Bill
-> Table Billing
-> Waiter addition rejected
-> Payment confirm
-> SO submitted
-> SI submitted with Update Stock = 1
-> stock reduced
-> Payment Entry/Entries submitted
-> SO restaurant status Closed
-> Table Available
```

Also verify:

- Print/reprint while printer is offline leaves the table Billing after server acceptance.
- Retrying a timed-out payment request does not create a second Sales Invoice or duplicate Payment Entry.
- Printed Sales Order total and final Sales Invoice total match.

## Acceptance Criteria

The cashier phase is accepted when all of the following are true:

1. Cashier sees active Open/Billing Draft Sales Orders without creating Sales Invoices during read-only refresh.
2. Print Bill freezes an Open order into Billing and prints the Draft Sales Order bill through the Windows printing path.
3. A Billing order rejects further waiter additions.
4. Payment can start from either Open or Billing.
5. Successful payment submits the Sales Order, creates/submits one Sales Invoice with Update Stock enabled, creates/submits required Payment Entries, and marks the restaurant order Closed.
6. Split payment works for Cash/Kpay style tenders and returns correct change behavior.
7. Retry does not duplicate final documents.
8. Amount mismatch stops checkout.
9. Table becomes Available only after successful finalization.
10. No Kitchen Monitor UI or Android direct printing dependency is reintroduced.
