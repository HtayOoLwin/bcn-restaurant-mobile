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

The customer bill is rendered from the Draft Sales Order before payment. A Sales Invoice is created only when payment is confirmed.

Cashier printing on OurCity uses a durable polling queue because the live safe-exec capability probe proved that `frappe.publish_realtime` is not exposed to Server Script code. The Windows printer client therefore polls HTTP API aliases for queued jobs instead of relying on a realtime `document_print_event` for cashier bills.

## Goals

- Preserve the one-Draft-Sales-Order-per-table restaurant flow.
- Allow cashier bill printing before payment.
- Freeze the order when printing or payment begins.
- Prevent waiter changes after the bill is frozen.
- Create accounting and stock documents only at payment finalization.
- Use Sales Invoice `update_stock = 1`; do not create a Delivery Note in this flow.
- Support Cash, Kpay, and split payment.
- Prevent duplicate Sales Invoices and Payment Entries when a payment request is retried.
- Keep printed bill totals and final Sales Invoice totals consistent.
- Return the table to Available only after successful payment finalization.
- Keep OurCity mobile APIs Server-Script-only.
- Use a durable `BCN Print Job` queue for cashier bill printing.
- Keep the Windows local printer client as the physical print executor.
- Preserve an audit trail for every print/reprint attempt.

## Non-goals

- Do not merge this branch into `main` as part of this work.
- Do not reintroduce Restaurant Table Session.
- Do not create a Delivery Note for cashier checkout.
- Do not submit the Sales Order from the waiter order API.
- Do not install the `bcn_restaurant` or `local_printers` custom app on OurCity as a requirement for this cashier flow.
- Do not use ERPNext Workflow as the primary state engine for restaurant order printing or payment.
- Kitchen delta printing is a separate phase.
- Do not make printer success a prerequisite for payment success.
- Do not automatically retry failed print jobs forever.
- Do not delete old print jobs after payment; they remain as audit records.

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
- `Print Bill` creates a print job and changes the order to `Billing` in the same request transaction.
- Starting Payment also changes the order to `Billing` inside the payment transaction before finalization begins.

### Billing

- Waiter changes are blocked.
- Cashier may reprint the bill.
- Cashier may complete payment regardless of print-job status.
- A failed/offline printer does not reopen the order.

### Closed

- The order is no longer returned by the active cashier list.
- The table is Available because there is no active Open/Billing Draft Sales Order.
- Closed is externally visible only after the whole payment transaction commits.

To avoid needing an after-submit edit on Sales Order, payment finalization sets `custom_restaurant_status = "Closed"` on the in-memory Draft Sales Order immediately before submission. Sales Order submission, Sales Invoice submission, Payment Entry submission, and the Closed value commit together. Any later failure rolls the transaction back.

## Required Site Configuration

The restaurant uses:

```text
Company      = Doh Myot Daw BBQ & Restaurant
POS Profile  = DMT
Price List   = Standard Selling
Currency     = MMK
```

Cashier printing is configured on POS Profile `DMT` with:

```text
custom_cashier_printer      Data
custom_cashier_print_format Link -> Print Format
```

`custom_cashier_printer` stores the exact Windows printer system name. `custom_cashier_print_format` must point to a Print Format for `Sales Order`.

A missing printer, missing print format, or a print format for the wrong DocType is a configuration error. The server does not select an arbitrary printer or silently fall back to Standard format.

Payment modes are read from the payment rows configured on POS Profile `DMT`. Each allowed Mode of Payment must resolve to a usable company account before checkout is enabled.

## Required Print Queue Configuration

### Custom DocType: `BCN Print Job`

Required fields:

```text
document_type        Data or Link-compatible text; cashier value = Sales Order
document_name        Data
printer_name         Data
print_format         Data or Link-compatible text
pdf_base64           Long Text
status               Select: Pending / Processing / Printed / Failed
attempt_count        Int
error_message        Long Text
requested_by         Data
requested_at         Datetime
claimed_by           Data
claimed_at           Datetime
printed_at           Datetime
```

The queue stores the original printable snapshot for that request. Reprint creates a new job and does not overwrite an earlier job.

### Role: `BCN Printer Client`

A dedicated ERPNext API user for each Windows printer client receives this role and an API Key/API Secret.

Security rules:

- Cashier/mobile users do not receive the printer API secret.
- The Flutter app never stores printer API credentials.
- `bcn_print_jobs` and `bcn_print_job_result` require the dedicated printer-client role.
- `claimed_by` is the authenticated ERPNext API user and is the ownership source of truth.
- PC hostname is not used as the security identity.
- Restaurant Manager/System Manager may inspect `BCN Print Job` records for support, but normal cashier users do not directly edit them.

## Live Capability Evidence and Remaining Gate

The OurCity capability probe against Draft Sales Order `SAL-ORD-2026-00005` established:

```text
SELECT ... FOR UPDATE       PASS
frappe.get_print(as_pdf=1)  PASS, 17,491 bytes
frappe.publish_realtime     FAIL: module has no attribute 'publish_realtime'
```

Therefore cashier printing must not depend on Server Script realtime publication.

The previous probe used `frappe.utils.pdf_to_base64(pdf_bytes)`, but that utility expects a PDF filename/path rather than raw PDF bytes, so that call is not a valid bytes-to-base64 solution.

Before production queue code is implemented, the implementation plan must run a focused safe-exec capability probe for raw-PDF-bytes -> base64 conversion. The approved queue payload remains `pdf_base64`.

- If a safe-exec-compatible conversion succeeds, use it and continue.
- If raw PDF bytes cannot be converted safely to base64 in Server Script, stop before implementing the queue transport and return to design. Do not silently change the payload to HTML, hex, File attachments, or require a custom app without explicit user approval.

This is an explicit deployment capability gate, not an invitation to change architecture during implementation.

## API Design

### `bcn_cashier_billing` — GET

Returns active Draft Sales Orders in `Open` or `Billing` state plus the payment modes available from POS Profile `DMT`.

Response shape:

```json
{
  "bills": [
    {
      "sales_order": "SAL-ORD-2026-00005",
      "customer": "Table 01",
      "customer_name": "Table 01",
      "creation": "2026-09-07 10:00:00",
      "net_total": 10000,
      "total_taxes_and_charges": 500,
      "grand_total": 10500,
      "currency": "MMK",
      "restaurant_status": "Open",
      "last_print_status": null,
      "last_print_job": null,
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

For Billing orders, `last_print_status` is the newest print job status for that Sales Order when one exists: `Pending`, `Processing`, `Printed`, or `Failed`.

The response is Sales Order based. It does not create or require a Sales Invoice.

### `bcn_cashier_print_bill` — POST

Input:

```json
{
  "sales_order": "SAL-ORD-2026-00005"
}
```

Rules:

1. Require an authenticated Cashier, Restaurant Manager, Administrator, or System Manager.
2. Load and lock the Draft Sales Order.
3. Reject cancelled, submitted, Closed, unknown, or out-of-scope orders.
4. Validate the DMT cashier printer and Sales Order print-format configuration.
5. Render the cashier bill snapshot from the Draft Sales Order.
6. Encode the snapshot into the approved `pdf_base64` queue payload.
7. Create a new `BCN Print Job` with `status = Pending`, `attempt_count = 0`, request metadata, configured printer, print format, document identifiers, and snapshot payload.
8. If status is `Open`, set `custom_restaurant_status = "Billing"` in the same transaction.
9. If status is already `Billing`, treat the request as a reprint and still create a new Pending job.
10. Return the queued result.

Response shape:

```json
{
  "sales_order": "SAL-ORD-2026-00005",
  "print_job": "PRINT-JOB-00001",
  "status": "Pending",
  "is_reprint": false
}
```

If PDF rendering, payload encoding, configuration validation, or print-job creation fails, the request fails and an Open order must remain Open. The Open -> Billing transition and Pending job creation commit together.

### `bcn_print_jobs` — POST claim API

This API is called by the Windows printer client using token authentication.

Request:

```json
{
  "printers": [
    "EPSON TM-T82III Receipt",
    "Cashier Printer"
  ]
}
```

Rules:

1. Require an authenticated user with `BCN Printer Client` role.
2. Reject an empty/invalid printer list.
3. Recover stale `Processing` jobs whose `claimed_at` is older than 60 seconds by making them claimable again.
4. Select the oldest `Pending` job whose `printer_name` exactly matches one of the supplied local printer names.
5. Lock the selected row with `SELECT ... FOR UPDATE` before changing claim state.
6. Change it to `Processing`.
7. Set `claimed_by = frappe.session.user`.
8. Set `claimed_at = now`.
9. Increment `attempt_count` by one.
10. Return exactly one claimed job per request.

Response when a job exists:

```json
{
  "job": {
    "name": "PRINT-JOB-00001",
    "document_type": "Sales Order",
    "document_name": "SAL-ORD-2026-00005",
    "printer_name": "EPSON TM-T82III Receipt",
    "print_format": "Restaurant Cashier Bill",
    "pdf_base64": "JVBERi0xLjQ...",
    "attempt_count": 1
  }
}
```

Response when no matching job exists:

```json
{
  "job": null
}
```

One poll claims at most one job. The client reports a result before claiming the next job.

### `bcn_print_job_result` — POST result API

Success request:

```json
{
  "job_name": "PRINT-JOB-00001",
  "status": "Printed"
}
```

Failure request:

```json
{
  "job_name": "PRINT-JOB-00001",
  "status": "Failed",
  "error_message": "SumatraPDF returned exit code 1"
}
```

Rules:

1. Require an authenticated user with `BCN Printer Client` role.
2. Lock the job.
3. Require current `status = Processing`.
4. Require `claimed_by == frappe.session.user`.
5. Accept only terminal result values `Printed` or `Failed`.
6. On `Printed`, set `printed_at = now` and clear stale error text.
7. On `Failed`, persist the exact client error in `error_message`.

Another printer API user cannot finish a job claimed by somebody else.

### `bcn_cashier_billing` — POST `action=Pay`

Input:

```json
{
  "action": "Pay",
  "sales_order": "SAL-ORD-2026-00005",
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
  "sales_order": "SAL-ORD-2026-00005",
  "sales_invoice": "ACC-SINV-2026-00001",
  "payment_entries": ["ACC-PAY-2026-00001"],
  "change_amount": 0,
  "duplicate": false
}
```

A retry after successful finalization returns the same final document identities with `duplicate = true`.

## Print Queue State Machine

```text
Pending
  -> claim
Processing
  -> success
Printed

Processing
  -> print error
Failed
```

Stale recovery:

```text
Processing with claimed_at older than 60 seconds
-> recover to claimable state
-> next valid client may claim
-> attempt_count increments on the new claim
```

Automatic infinite retry is not allowed. A normal Failed job remains Failed. Cashier `Reprint Bill` creates a fresh Pending job, leaving the failed job untouched for audit.

## Print/Payment Interaction

Print status and payment status are intentionally loosely coupled.

```text
Print job Pending     -> payment allowed
Print job Processing  -> payment allowed
Print job Printed     -> payment allowed
Print job Failed      -> payment allowed
```

Printer failure is not payment failure.

If payment completes while an older print job is still Pending or Processing, that queued snapshot may still print afterward. The job is not automatically cancelled merely because the Sales Order has been finalized.

Old print jobs are never deleted by payment finalization.

A reprint after payment uses the original bill snapshot already stored in the relevant print job history rather than changing the source document to the final Sales Invoice. The customer-facing bill remains consistent with the pre-payment snapshot.

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
lastPrintStatus
lastPrintJob
items
taxes
```

The current mobile payment tender concept remains suitable for Cash, Kpay, and split payment.

## Cashier UI Behavior

### Open bill card

- Status chip: `Open`
- Actions: `Print Bill`, `Payment`
- Merely opening or refreshing the cashier screen does not freeze the order.

### Billing bill card

- Status chip: `Billing`
- Actions: `Reprint Bill`, `Payment`
- Waiter additions are rejected by the server.
- Show `Last Print: Pending`, `Processing`, `Printed`, or `Failed` when history exists.

### Failed print

- Show a cashier-friendly short failure state.
- Keep the exact Windows/Sumatra error in `BCN Print Job.error_message` for support/audit.
- `Reprint Bill` creates a new Pending job.

### Payment success

- Cashier bill card disappears from the active list.
- Cashier provider refreshes.
- Dine In and Takeaway table providers refresh.
- The table becomes Available.

## Windows Printer Client

The Windows application continues to use the existing physical print path and SumatraPDF behavior. Cashier transport changes from Socket.IO realtime delivery to HTTP polling.

Existing legacy Socket.IO behavior is not removed merely to implement cashier polling. The new cashier polling path must be introduced without breaking unrelated legacy/kitchen printing paths that may still depend on existing event listeners.

Required cashier polling flow:

```text
Startup
-> load config
-> detect local Windows printer names
-> build Authorization: token API_KEY:API_SECRET
-> every 2 seconds call bcn_print_jobs with local printer names
-> job = null: wait and poll again
-> job returned: decode pdf_base64
-> send PDF through existing SumatraPDF silent-print path
-> POST bcn_print_job_result as Printed or Failed
-> only after result reporting, claim next job
```

The Windows config must support:

```text
FRAPPE_BASE_URL
API_KEY
API_SECRET
POLL_INTERVAL_SECONDS = 2
SUMATRA_PDF_PATH
```

`AUTH_DATA`/Socket.IO session configuration may remain for legacy event handling if that path is still enabled, but cashier polling must not depend on it.

## Payment Validation

The server validates all tender amounts before submitting the Sales Order.

Rules:

- A tender row must have a configured Mode of Payment and a positive amount.
- At least one positive tender is required.
- Non-cash tender total may not exceed the invoice amount.
- Cash may exceed the remaining amount; the excess is returned as `change_amount`.
- Overpayment is valid only when the excess is represented by Cash.
- The total usable tender must cover the amount due.
- Each Payment Entry allocates at most the remaining invoice amount.
- Cash tender above the amount due is not posted as extra receivable settlement; it is returned as change.

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

The Draft Sales Order is the source of the bill the customer sees before payment. Tax/service-charge configuration must therefore already be applied while the Sales Order is Draft.

`bcn_mobile_create_order` must apply the DMT selling/tax configuration when a Draft Sales Order is created and must preserve/recalculate the same tax rows when later waiter rounds modify quantities.

The DMT POS Profile and its configured selling/tax setup are the source of truth for restaurant checkout.

Required consistency rules, subject only to normal currency rounding tolerance:

```text
Billing Sales Order Net Total == Final Sales Invoice Net Total
Billing Sales Order Total Taxes and Charges == Final Sales Invoice Total Taxes and Charges
Billing Sales Order Grand Total == Final Sales Invoice Grand Total
```

If the generated Sales Invoice differs from the frozen Billing Sales Order, payment finalization stops and the transaction rolls back.

## Idempotency and Concurrency

### Payment

Payment finalization must be retry-safe.

The Sales Order is locked during finalization so two cashier devices cannot finalize the same table simultaneously.

The standard Sales Invoice Item -> Sales Order linkage is the deterministic finalization link. On retry of a submitted Closed Sales Order, the server finds submitted Sales Invoices whose items reference that Sales Order:

- exactly one matching Sales Invoice -> reuse it;
- no matching Sales Invoice -> inconsistent finalization error;
- more than one matching Sales Invoice -> conflict error.

Payment Entries are resolved through submitted Payment Entry Reference rows for that Sales Invoice. Retry returns the existing document names instead of creating duplicates.

### Print

- Open -> Billing occurs only when a Pending print job is successfully created.
- Further print requests while Billing are reprints and create new jobs.
- Claim uses row locking so two clients do not intentionally claim the same Pending record.
- Result ownership is enforced by `claimed_by`.
- Stale Processing recovery is allowed after 60 seconds.

Polling and process crashes cannot provide an absolute exactly-once physical-paper guarantee: a Windows process could physically print and crash before reporting `Printed`, causing stale recovery to print the same snapshot again. This design provides durable job state and at-least-once recovery semantics. Duplicate physical output in that narrow crash window is acceptable for v1 and is preferable to silently losing the bill.

## Transaction Boundaries

### Print request

The following commit together:

```text
Draft SO validation
+ PDF snapshot generation/encoding
+ new Pending BCN Print Job
+ Open -> Billing transition when applicable
```

If queue creation fails, an Open Sales Order remains Open.

### Claim

Job row selection and `Pending -> Processing` claim metadata update occur in one transaction under row lock.

### Result

Ownership validation and `Processing -> Printed/Failed` update occur in one request transaction.

### Payment

Payment finalization is one server request and one database transaction from validation through final document creation.

If any of these fail:

- Sales Order submit
- Sales Invoice creation
- Sales Invoice total validation
- Sales Invoice submit
- Payment Entry creation/submission
- final outstanding validation

then the request returns an error and the database transaction is rolled back. The externally visible table/order state remains at its pre-request state.

## Error Handling

Cashier-facing errors identify actionable conditions without exposing stack traces.

Examples:

- Table/order no longer exists.
- Order is already cancelled or is in an invalid state.
- More than one active Draft Sales Order exists for the same table.
- Order is Billing and waiter tries to add more items.
- DMT cashier printer or Sales Order print format is not configured.
- Print snapshot cannot be generated or encoded.
- Print queue record cannot be created.
- Payment mode is unavailable or has no usable company account.
- Tender total is insufficient.
- Non-cash overpayment is not allowed.
- Sales Invoice amount does not match the frozen bill.
- Stock validation prevents Sales Invoice submission.
- Submitted Closed Sales Order has zero or multiple linked final Sales Invoices.

Printer-client API errors include:

- Missing `BCN Printer Client` role.
- Empty printer list.
- Job does not exist.
- Job is not currently Processing.
- Job is owned by a different printer API user.
- Unsupported result status.

## Expected Files and Repositories to Change

### `HtayOoLwin/bcn-restaurant-mobile`

Server-script mirrors and docs:

```text
server_scripts/mobile/create_order.py
server_scripts/mobile/cashier_billing.py
server_scripts/mobile/cashier_print_bill.py
server_scripts/mobile/print_jobs.py
server_scripts/mobile/print_job_result.py
docs/server-script-mobile.md
```

Flutter:

```text
mobile/bcn_restaurant_mobile/lib/features/cashier/data/cashier_repository.dart
mobile/bcn_restaurant_mobile/lib/features/cashier/domain/cashier_models.dart
mobile/bcn_restaurant_mobile/lib/features/cashier/presentation/cashier_screen.dart
mobile/bcn_restaurant_mobile/lib/features/printing/data/windows_print_repository.dart
mobile/bcn_restaurant_mobile/lib/features/printing/domain/cashier_bill_print_result.dart
```

Tests:

```text
tests/test_ourcity_server_script_contract.py
mobile/bcn_restaurant_mobile/test/features/cashier/cashier_models_test.dart
mobile/bcn_restaurant_mobile/test/features/cashier/cashier_repository_test.dart
mobile/bcn_restaurant_mobile/test/features/cashier/cashier_screen_test.dart
mobile/bcn_restaurant_mobile/test/features/printing/windows_print_repository_test.dart
```

### `HtayOoLwin/local_printers_winapp`

Expected Windows-side changes:

```text
socket_app.py or a focused polling module called by it
printer_handlers.py only if needed to expose a reusable single-job PDF print function
config copy.json
Windows polling tests
README.md
```

The implementation should prefer a focused polling module over turning `socket_app.py` into a single large mixed-responsibility file.

## Deployment Setup on OurCity

Manual setup required before end-to-end acceptance:

```text
1. Create Custom DocType BCN Print Job with the approved fields/status values.
2. Create Role BCN Printer Client.
3. Create a dedicated printer API user and assign BCN Printer Client.
4. Generate API Key/API Secret for that printer user.
5. Add POS Profile DMT custom_cashier_printer.
6. Add POS Profile DMT custom_cashier_print_format.
7. Deploy/update bcn_mobile_create_order.
8. Deploy bcn_cashier_billing.
9. Deploy bcn_cashier_print_bill.
10. Deploy bcn_print_jobs.
11. Deploy bcn_print_job_result.
12. Configure Windows FRAPPE_BASE_URL/API token/poll interval/Sumatra path.
```

Server Script source-control files are mirrors and must be copied/deployed into the corresponding OurCity Server Script records; pushing the Git branch alone does not deploy them.

## Testing Requirements

### Server contract tests

Must cover:

- Cashier GET returns active Open/Billing Draft Sales Orders.
- `bcn_mobile_create_order` applies/recalculates DMT tax/service-charge state.
- Billing blocks waiter changes.
- Print Bill creates a new Pending job.
- Open -> Billing happens only when print-job creation succeeds.
- Pending job contains the Draft Sales Order print snapshot and configured printer/format.
- Reprint creates a new job and leaves earlier jobs unchanged.
- Claim requires `BCN Printer Client`.
- Claim matches exact local printer names.
- Claim chooses oldest matching Pending job.
- Claim uses `FOR UPDATE`.
- Claim changes Pending -> Processing and increments attempt count.
- Claim ownership is stored in `claimed_by`.
- Stale Processing > 60 seconds becomes claimable again.
- Result accepts only Printed/Failed.
- Wrong API user cannot complete another user's claimed job.
- Payment works regardless of latest print status.
- Sales Invoice uses `update_stock = 1`.
- Sales Order/Sales Invoice total mismatch blocks checkout.
- Split payment and cash change allocate correctly.
- Payment retry resolves exactly one linked submitted Sales Invoice and existing Payment Entries.

### Flutter tests

Must cover:

- Draft SO bill parsing.
- Last print status parsing.
- Open card shows Print Bill + Payment.
- Billing card shows Reprint Bill + Payment.
- Payment payload uses `sales_order` and tender list.
- Print request uses `sales_order`.
- Successful payment refreshes cashier/table providers and removes Closed bill from active list.

### Windows tests

Must cover:

- Exact token Authorization header.
- Local printer names are sent to `bcn_print_jobs`.
- Poll interval uses configured 2-second default.
- `job = null` is handled without error.
- `pdf_base64` is decoded to PDF bytes.
- Existing SumatraPDF print path is used.
- Printed result is reported on success.
- Failed result includes the exact print exception/error.
- Client does not claim the next job until the current result has been reported.
- Existing legacy Socket.IO behavior is not accidentally broken by cashier polling changes.

## Acceptance Scenarios

### Happy path

```text
Table 01 waiter order
-> Draft SO Open
-> table Occupied
-> cashier sees bill
-> Print Bill
-> Pending BCN Print Job created
-> SO Billing
-> waiter add-item attempt rejected
-> Windows app claims job -> Processing
-> receipt prints
-> job -> Printed
-> cashier confirms Payment
-> SO set Closed and submitted
-> one Sales Invoice submitted with Update Stock = 1
-> stock reduced
-> Payment Entry/Entries submitted
-> invoice outstanding = 0
-> table Available
-> cashier card disappears
```

### Printer offline/failure

```text
Print Bill
-> Pending job created
-> SO Billing
-> printer unavailable / job fails
-> Pending or Failed remains visible in audit
-> waiter stays locked
-> cashier may still complete Payment
-> cashier may Reprint, creating a new Pending job
```

### Process crash after physical print but before result POST

```text
job Processing
-> paper physically prints
-> Windows process crashes before reporting Printed
-> after >60 sec job becomes claimable
-> same snapshot may print again
```

This at-least-once duplicate risk is explicitly accepted for v1.

### Payment retry

```text
first Pay request commits successfully
-> client times out before receiving response
-> retry same Sales Order
-> server finds exactly one linked submitted Sales Invoice
-> resolves existing Payment Entries
-> returns same identities with duplicate = true
-> no duplicate invoice or payment entry is created
```

## Final Architecture

```text
Waiter
  -> one Open Draft Sales Order per table

Cashier
  -> GET Open/Billing Draft SO bills
  -> Print Bill/Reprint
       -> Draft SO snapshot
       -> new BCN Print Job Pending
       -> Open -> Billing when needed
  -> Payment
       -> lock/freeze totals
       -> SO Closed + submit
       -> Sales Invoice + Update Stock = 1
       -> Payment Entry/Entries
       -> table Available

Windows Printer Client
  -> token-auth HTTP polling every ~2 seconds
  -> claim oldest matching Pending job
  -> Processing
  -> SumatraPDF silent print
  -> report Printed or Failed

OurCity
  -> Server Script API aliases only
  -> no cashier realtime publish dependency
  -> no required custom-app installation
```
