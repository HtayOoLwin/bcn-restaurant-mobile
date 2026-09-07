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
- Durable printer-job acknowledgements are not required in the Server-Script-only cashier path; cashier recovery is manual Reprint Bill.

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
- Starting Payment also changes the order to `Billing` inside the payment transaction before finalization begins.

### Billing

- Waiter changes are blocked.
- Cashier may reprint the bill.
- Cashier may complete payment.
- Printer failure after the print event has been accepted does not reopen the order.

### Closed

- The order is no longer returned by the active cashier list.
- The table is Available because there is no active Open/Billing Draft Sales Order.
- Closed is externally visible only after the whole payment transaction commits.

To avoid needing an after-submit edit on Sales Order, payment finalization sets `custom_restaurant_status = "Closed"` on the in-memory Draft Sales Order immediately before submission. Sales Order submission, Sales Invoice submission, Payment Entry submission, and the Closed value commit together. Any later failure rolls the transaction back, so other users never observe a partially finalized Closed order.

## Required Site Configuration

The restaurant uses:

```text
Company      = Doh Myot Daw BBQ & Restaurant
POS Profile  = DMT
Price List   = Standard Selling
Currency     = MMK
```

Cashier printing is configured on POS Profile `DMT` with two custom fields:

```text
custom_cashier_printer      Data
custom_cashier_print_format Link -> Print Format
```

`custom_cashier_printer` stores the exact Windows printer system name expected by the Windows local-printer application. `custom_cashier_print_format` must point to a Print Format for `Sales Order`.

A missing printer, missing print format, or a print format for the wrong DocType is a configuration error. The server does not select an arbitrary printer or silently fall back to Standard format.

Payment modes are read from the payment rows configured on POS Profile `DMT`. Each allowed Mode of Payment must resolve to a usable company account before checkout is enabled.

## API Design

### `bcn_cashier_billing` — GET

Returns active Draft Sales Orders in `Open` or `Billing` state plus the payment modes available from POS Profile `DMT`.

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
      "taxes": []
    }
  ],
  "modes": [
    {"name": "Cash", "default": true},
    {"name": "Kpay", "default": false}
  ]
}
```

The response is Sales Order based. It does not create or require a Sales Invoice.

### `bcn_cashier_print_bill` — POST

Input:

```json
{
  "sales_order": "SAL-ORD-2026-00001"
}
```

Rules:

1. Require an authenticated Cashier, Restaurant Manager, Administrator, or System Manager.
2. Load and lock the Draft Sales Order.
3. Reject cancelled, submitted, Closed, unknown, or out-of-scope orders.
4. If status is `Open`, set `custom_restaurant_status = "Billing"`.
5. If status is already `Billing`, treat the request as a reprint.
6. Validate the DMT cashier printer and Sales Order print format configuration.
7. Render the cashier bill from the Draft Sales Order.
8. Publish `document_print_event` with one cashier PDF job.
9. Return the accepted result:

```json
{
  "sales_order": "SAL-ORD-2026-00001",
  "status": "accepted",
  "is_reprint": false
}
```

A failure before the print event is published rolls back the Open -> Billing transition. A failure on the Windows machine after event publication leaves the order in Billing; the cashier uses Reprint Bill.

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

1. Require an authenticated Cashier, Restaurant Manager, Administrator, or System Manager.
2. Lock the Sales Order and validate it is the one active restaurant order for its customer/table.
3. If the Sales Order is already submitted and Closed, resolve and return its existing finalized documents instead of creating new ones.
4. Move `Open` to `Billing` inside the transaction if payment started without a prior bill print.
5. Validate all tenders and payment-mode accounts before creating accounting documents.
6. Freeze the Draft Sales Order totals and validate its tax/service-charge state.
7. Set the in-memory Sales Order restaurant status to `Closed` and submit the Sales Order.
8. Create one Sales Invoice from the Sales Order with `update_stock = 1`.
9. Preserve Sales Order references on Sales Invoice Items.
10. Validate Sales Invoice totals against the frozen Sales Order totals.
11. Submit the Sales Invoice.
12. Create one submitted Payment Entry per positive usable tender allocation.
13. Verify the Sales Invoice is fully settled.
14. Return the final result.

Response shape:

```json
{
  "sales_order": "SAL-ORD-2026-00001",
  "sales_invoice": "ACC-SINV-2026-00001",
  "payment_entries": ["ACC-PAY-2026-00001"],
  "change_amount": 0,
  "duplicate": false
}
```

A retry after successful finalization returns the same final document identities with `duplicate = true`.

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
```

No extra Sales Order fields are needed to track `bill_printed`. An externally visible `Billing` Draft Sales Order is the frozen/reprint state. A payment request that fails rolls back to the pre-request state; a successful payment becomes Closed and disappears from the active list.

The current mobile payment tender concept remains suitable for Cash, Kpay, and split payment.

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

### Print status handling

The cashier flow does not depend on the existing custom-app print-status/retry endpoints. Server acceptance means the realtime print event was published; it does not prove that paper physically printed. Operational recovery is `Reprint Bill` while the Sales Order remains Billing.

## Print Source and Windows Print Transport

The cashier bill is rendered from the Draft Sales Order, not from a Sales Invoice.

The existing Windows client listens for `document_print_event` and accepts jobs containing a base64 PDF, printer name, print format, and document identifiers. The cashier print API uses that event contract.

Representative event shape:

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
      "printer": "Windows Cashier Printer",
      "is_cashier": true,
      "print_format": "Restaurant Cashier Bill",
      "pdf_base64": "BASE64_PDF_CONTENT"
    }
  ]
}
```

The values above are example payload values; runtime printer and print-format values come from POS Profile `DMT` configuration.

OurCity continues to expose mobile endpoints through Frappe Server Script API aliases. The implementation must use APIs available inside Server Script safe execution. It must not depend on importing `bcn_restaurant` or `local_printers` Python modules on OurCity.

Because PDF rendering, base64 encoding, and realtime publishing are platform-sensitive inside Server Script safe execution, the implementation plan begins by proving this exact path on OurCity. If safe execution blocks any required primitive, that is treated as a deployment blocker for the Server-Script-only print path; the implementation must not silently change the approved architecture to a custom-app installation.

## Payment Validation

The server validates all tender amounts before submitting the Sales Order.

Rules:

- A tender row must have a configured Mode of Payment and a positive amount.
- At least one positive tender is required.
- Non-cash tender total may not exceed the invoice amount.
- Cash may exceed the remaining amount; the excess is returned as `change_amount`.
- Overpayment is valid only when the excess is represented by Cash.
- The total usable tender must cover the amount due.
- Each Payment Entry allocates at most the remaining invoice amount. Cash tender above the amount due is not posted as extra receivable settlement; it is returned as change.

Example:

```text
Amount due: 10,500
Kpay tender: 5,500 -> Payment Entry allocation 5,500
Cash tender: 6,000 -> Payment Entry allocation 5,000
Change: 1,000
```

For split payment, each positive usable tender allocation creates its own Payment Entry after Sales Invoice submission.

## Stock Handling

The checkout path uses:

```text
Sales Invoice
update_stock = 1
```

No Delivery Note is created. Stock reduction happens when the Sales Invoice is submitted.

The generated Sales Invoice must preserve standard Sales Order linkage on each invoice item, including the Sales Order name and source Sales Order Item reference where ERPNext supports them.

## Tax and Service Charge Consistency

The Draft Sales Order is the source of the bill the customer sees before payment. Therefore tax/service-charge configuration must already be applied while the Sales Order is Draft.

`bcn_mobile_create_order` must apply the DMT selling/tax configuration when a Draft Sales Order is created and must preserve/recalculate the same tax rows when later waiter rounds modify quantities.

The DMT POS Profile and its configured selling/tax setup are the source of truth for restaurant checkout.

Required consistency rules, subject only to normal currency rounding tolerance:

```text
Billing Sales Order Net Total == Final Sales Invoice Net Total
Billing Sales Order Total Taxes and Charges == Final Sales Invoice Total Taxes and Charges
Billing Sales Order Grand Total == Final Sales Invoice Grand Total
```

If the generated Sales Invoice differs from the frozen Billing Sales Order, payment finalization stops and the transaction rolls back. The server does not silently accept a changed amount.

## Idempotency and Concurrency

### Payment

Payment finalization must be retry-safe.

The Sales Order is locked during finalization so two cashier devices cannot finalize the same table simultaneously.

The standard Sales Invoice Item -> Sales Order linkage is the deterministic finalization link. On retry of a submitted Closed Sales Order, the server finds submitted Sales Invoices whose items reference that Sales Order:

- exactly one matching Sales Invoice -> reuse it;
- no matching Sales Invoice -> treat as an inconsistent finalization and return an error;
- more than one matching Sales Invoice -> return a conflict error instead of guessing.

Payment Entries are resolved through their submitted Payment Entry Reference rows for that Sales Invoice. The retry response returns those existing document names instead of creating duplicates.

### Print

An Open -> Billing transition occurs once. Further print requests while Billing are reprints and do not alter financial state.

## Transaction Boundaries

Payment finalization is one server request and one database transaction from validation through final document creation.

If any of these fail:

- Sales Order submit
- Sales Invoice creation
- Sales Invoice total validation
- Sales Invoice submit
- Payment Entry creation/submission
- final outstanding validation

then the request returns an error and the database transaction is rolled back. The externally visible table/order state remains at its pre-request state.

The print path is separate from payment. A realtime print event accepted by the server may still fail later on the Windows machine; that operational failure does not reopen the bill.

## Error Handling

User-facing failures identify the actionable condition without exposing stack traces.

Examples:

- Table/order no longer exists.
- Order is already cancelled or is in an invalid state.
- More than one active Draft Sales Order exists for the same table.
- Order is Billing and waiter tries to add more items.
- DMT cashier printer or Sales Order print format is not configured.
- Payment mode is unavailable or has no usable company account.
- Tender total is insufficient.
- Non-cash overpayment is not allowed.
- Sales Invoice amount does not match the frozen bill.
- Stock validation prevents Sales Invoice submission.
- Submitted Closed Sales Order has zero or multiple linked final Sales Invoices.

## Files and Components Expected to Change

Server-script mirror and docs:

```text
server_scripts/mobile/cashier_billing.py
server_scripts/mobile/cashier_print_bill.py
server_scripts/mobile/create_order.py
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
- create-order applies/preserves DMT tax/service-charge configuration;
- print changes Open to Billing and supports Billing reprint;
- print reads DMT cashier printer and Sales Order print format configuration;
- payment uses the Sales Order identifier rather than invoice-first input;
- final Sales Invoice uses Update Stock;
- payment completion commits Closed state;
- amount mismatch blocks completion;
- retry logic resolves the one linked final Sales Invoice instead of duplicating it.

### Flutter tests

Verify:

- Sales Order bill JSON parsing;
- Open card shows Print Bill + Payment;
- Billing card shows Reprint Bill + Payment;
- payment request sends Sales Order and tender list;
- successful payment refreshes cashier and table providers;
- closed bill disappears after refresh;
- cashier printing calls the OurCity Server Script alias rather than custom-app dotted print methods.

### OurCity print-path proof

Before production print wiring, prove on OurCity Server Script safe execution that the implementation can:

1. render the configured Sales Order Print Format as PDF;
2. base64-encode the result;
3. publish `document_print_event` to the site realtime namespace;
4. deliver a representative PDF job to the connected Windows client.

This proof is required because OurCity uses Server Script API aliases rather than importing the custom printing app.

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

- Reprint while the Windows printer is unavailable leaves the table Billing after server event acceptance.
- Retrying a timed-out successful payment request does not create a second Sales Invoice or duplicate Payment Entry.
- Printed Sales Order totals and final Sales Invoice totals match.
- Cash over-tender creates the correct change without over-allocating the Payment Entry.

## Acceptance Criteria

The cashier phase is accepted when all of the following are true:

1. Cashier sees active Open/Billing Draft Sales Orders without creating Sales Invoices during read-only refresh.
2. Print Bill freezes an Open order into Billing and publishes the Draft Sales Order bill through the Windows printing path.
3. A Billing order rejects further waiter additions.
4. Payment can start from either Open or Billing.
5. Successful payment submits the Sales Order, creates/submits one Sales Invoice with Update Stock enabled, creates/submits required Payment Entries, and commits the restaurant order as Closed.
6. Split payment works for configured Cash/Kpay-style tenders and returns correct change behavior.
7. Retry resolves existing final documents and does not duplicate them.
8. Amount mismatch stops checkout and rolls back the payment request.
9. Table becomes Available only after successful finalization commits.
10. No Kitchen Monitor UI or Android direct printing dependency is reintroduced.
11. Cashier printing uses the Server-Script-compatible `document_print_event` path without requiring BCN Restaurant or Local Printers Python module imports on OurCity.
