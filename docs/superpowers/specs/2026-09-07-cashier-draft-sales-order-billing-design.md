# Cashier Draft Sales Order Billing Design

Date: 2026-09-07  
Target branch: `bcn-restaurant-mobile-without-kitchen-monitor`  
Target site: `https://ourcity.s.frappe.cloud`

## Summary

The restaurant mobile flow keeps one active Draft Sales Order per table visit. Waiters may add items while the order is `Open`. Cashier work starts from that Draft Sales Order instead of creating a Sales Invoice early.

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

Cashier printing on OurCity uses a durable polling queue. A live safe-exec probe proved that `frappe.publish_realtime` is not exposed to Server Script code, so cashier printing must not depend on realtime `document_print_event` publication.

## Goals

- Preserve one active Draft Sales Order per table/customer visit.
- Allow bill printing before payment.
- Freeze waiter edits when printing or payment begins.
- Create accounting and stock documents only at payment finalization.
- Use Sales Invoice `update_stock = 1`; do not create a Delivery Note.
- Support Cash, Kpay, and split payment.
- Make payment retry-safe.
- Keep printed Draft Sales Order totals equal to final Sales Invoice totals.
- Return the table to Available only after successful finalization.
- Keep OurCity mobile APIs Server-Script-only.
- Use a durable `BCN Print Job` polling queue for cashier bills.
- Keep the Windows local-printer app as the physical print executor.
- Preserve print/reprint audit history.

## Non-goals

- Do not merge this branch into `main` as part of this work.
- Do not reintroduce Restaurant Table Session.
- Do not create a Delivery Note for checkout.
- Do not submit the Sales Order from the waiter order API.
- Do not require installation of `bcn_restaurant` or `local_printers` on OurCity.
- Do not use ERPNext Workflow as the primary order/payment state engine.
- Kitchen delta printing remains a separate phase.
- Do not make successful physical printing a prerequisite for payment.
- Do not automatically retry Failed print jobs forever.
- Do not delete old print jobs after payment.

## Fixed Restaurant Configuration

```text
Company      = Doh Myot Daw BBQ & Restaurant
POS Profile  = DMT
Price List   = Standard Selling
Currency     = MMK
```

POS Profile `DMT` requires:

```text
custom_cashier_printer      Data
custom_cashier_print_format Link -> Print Format
```

`custom_cashier_printer` stores the exact Windows printer system name. `custom_cashier_print_format` must reference a Print Format whose DocType is `Sales Order`.

Missing or invalid printer/print-format configuration is an error. There is no arbitrary fallback printer or silent fallback to Standard format.

Payment modes come from POS Profile `DMT`. Each usable Mode of Payment must resolve to a company account before checkout succeeds.

## Restaurant State Machine

The active order is a Sales Order with one of these `custom_restaurant_status` values:

```text
Open
Billing
Closed
```

Table derivation remains:

```text
No Open/Billing Draft SO -> Available
Open Draft SO            -> Occupied
Billing Draft SO         -> Billing
```

### Open

- Cashier viewing does not change state.
- Waiter may append items.
- Print Bill creates a Pending print job and changes Open -> Billing in the same request transaction.
- Starting Payment may move Open -> Billing inside the payment transaction.

### Billing

- Waiter item changes are rejected.
- Cashier may Reprint Bill.
- Cashier may complete Payment regardless of print-job status.
- Printer failure does not reopen the order.

### Closed

- The order is not returned by the active cashier bill list.
- The table becomes Available after the payment transaction commits.
- `Closed` is assigned on the in-memory Draft Sales Order immediately before submission so SO submission, SI submission, PE submission, and Closed state commit atomically.

## Custom DocType: `BCN Print Job`

Create a custom DocType with these exact fields:

```text
document_type   Link -> DocType
document_name   Dynamic Link -> options: document_type
printer_name    Data
print_format    Link -> Print Format
pdf_base64      Long Text
status          Select: Pending\nProcessing\nPrinted\nFailed
attempt_count   Int
error_message   Long Text
requested_by    Link -> User
requested_at    Datetime
claimed_by      Link -> User
claimed_at      Datetime
printed_at      Datetime
```

The document `name` is an opaque Frappe-generated identifier. Clients must not parse or depend on a specific naming-series format.

Each print request stores an immutable printable snapshot in its own job. Reprint creates a new job; previous jobs are not overwritten.

## Printer Client Security

Create Role:

```text
BCN Printer Client
```

Use a dedicated ERPNext API user for each Windows printer client. The client authenticates with:

```http
Authorization: token API_KEY:API_SECRET
```

Rules:

- Flutter/mobile users never receive the printer API secret.
- Cashier users do not directly edit `BCN Print Job` records.
- `bcn_print_jobs` and `bcn_print_job_result` require `BCN Printer Client`.
- `claimed_by` uses the authenticated ERPNext user and is the ownership source of truth.
- PC hostname is not a security identity.
- Restaurant Manager/System Manager may inspect queue records for support.

## Live Capability Evidence and Remaining Capability Gate

The OurCity probe against `SAL-ORD-2026-00005` established:

```text
SELECT ... FOR UPDATE       PASS
frappe.get_print(as_pdf=1)  PASS, 17,491 bytes
frappe.publish_realtime     FAIL: module has no attribute 'publish_realtime'
```

The earlier probe also showed that `frappe.utils.pdf_to_base64(pdf_bytes)` is not a valid raw-bytes encoder because that utility expects a PDF filename/path.

Before production queue implementation, run a focused safe-exec probe for:

```text
raw PDF bytes -> base64 string
```

The approved queue payload is `pdf_base64`.

- If a safe-exec-compatible raw-bytes encoder works, continue.
- If not, stop before implementing queue transport and return to design.
- Do not silently change the payload to HTML, hex, File attachments, or a custom-app method.

## API: `bcn_cashier_billing` GET

Returns Open/Billing Draft Sales Orders and DMT payment modes.

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

For a bill with print history, `last_print_status` and `last_print_job` come from the newest `BCN Print Job` for that Sales Order.

GET does not create a Sales Invoice and does not freeze the order.

## API: `bcn_cashier_print_bill` POST

Request:

```json
{
  "sales_order": "SAL-ORD-2026-00005"
}
```

### Draft Open/Billing behavior

1. Require Cashier, Restaurant Manager, Administrator, or System Manager.
2. Lock the Draft Sales Order.
3. Reject cancelled, unknown, out-of-scope, or invalid-state orders.
4. Validate DMT printer and Sales Order print format.
5. Render the Draft Sales Order bill snapshot.
6. Encode the PDF as `pdf_base64`.
7. Create a new `BCN Print Job` with:
   - `document_type = Sales Order`
   - the Sales Order name
   - configured printer/format
   - immutable PDF snapshot
   - `status = Pending`
   - `attempt_count = 0`
   - request user/time
8. If the Sales Order is Open, set it to Billing in the same transaction.
9. If already Billing, the new job is a reprint.

Response:

```json
{
  "sales_order": "SAL-ORD-2026-00005",
  "print_job": "PRINT-JOB-EXAMPLE",
  "status": "Pending",
  "is_reprint": false
}
```

If config validation, rendering, encoding, or job creation fails, the request fails and an Open Sales Order remains Open.

### Submitted Closed reprint behavior

The approved workflow allows reprinting immediately after payment without changing the source to Sales Invoice.

For a submitted Sales Order with `custom_restaurant_status = Closed`:

1. Require the same cashier/manager roles.
2. Find the newest existing `BCN Print Job` for that Sales Order.
3. If no previous snapshot exists, return a clear `No printable cashier snapshot exists` error.
4. Create a new Pending job by copying the previous job's `pdf_base64`, printer name, and print format.
5. Do not re-render the submitted Sales Order and do not render the Sales Invoice.
6. Do not alter Sales Order state.
7. Return `is_reprint = true`.

This keeps post-payment reprint output equal to the original pre-payment customer bill.

## API: `bcn_print_jobs` POST

Called by the Windows printer client.

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

1. Require `BCN Printer Client`.
2. Require at least one non-empty printer name.
3. Normalize stale jobs: any `Processing` job with `claimed_at` older than 60 seconds becomes claimable again; clear stale `claimed_by` and `claimed_at` before the new claim.
4. Select the oldest `Pending` job whose `printer_name` exactly matches one supplied printer.
5. Lock the selected job with `SELECT ... FOR UPDATE`.
6. Set `status = Processing`.
7. Set `claimed_by = frappe.session.user`.
8. Set `claimed_at = now`.
9. Increment `attempt_count` by one.
10. Return exactly one job.

Job response:

```json
{
  "job": {
    "name": "PRINT-JOB-EXAMPLE",
    "document_type": "Sales Order",
    "document_name": "SAL-ORD-2026-00005",
    "printer_name": "EPSON TM-T82III Receipt",
    "print_format": "Restaurant Cashier Bill",
    "pdf_base64": "JVBERi0xLjQ...",
    "attempt_count": 1
  }
}
```

No-job response:

```json
{
  "job": null
}
```

One poll claims at most one job. The client reports the current job result before intentionally claiming the next one.

## API: `bcn_print_job_result` POST

Success:

```json
{
  "job_name": "PRINT-JOB-EXAMPLE",
  "status": "Printed"
}
```

Failure:

```json
{
  "job_name": "PRINT-JOB-EXAMPLE",
  "status": "Failed",
  "error_message": "SumatraPDF returned exit code 1"
}
```

Rules:

1. Require `BCN Printer Client`.
2. Lock the job.
3. Accept requested result values only `Printed` or `Failed`.
4. Require `claimed_by == frappe.session.user`.
5. If current status is `Processing`, apply the requested terminal result.
6. If current status already equals the requested terminal result and ownership still matches, return success with `duplicate = true` without changing data. This makes result POST retry-safe after a response timeout.
7. If current status is the other terminal state, reject as a conflict.
8. On Printed, set `printed_at = now` and clear `error_message`.
9. On Failed, store the exact client print error.

Normal first response:

```json
{
  "job_name": "PRINT-JOB-EXAMPLE",
  "status": "Printed",
  "duplicate": false
}
```

Idempotent retry response:

```json
{
  "job_name": "PRINT-JOB-EXAMPLE",
  "status": "Printed",
  "duplicate": true
}
```

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

A normal Failed job remains Failed. Cashier Reprint creates a new Pending job.

Stale recovery:

```text
Processing + claimed_at older than 60 seconds
-> clear old claim
-> Pending/claimable
-> next valid client may claim
-> attempt_count increments on claim
```

Exactly-once physical paper output cannot be guaranteed. A Windows process may physically print and crash before reporting Printed; stale recovery can then print that snapshot again. This v1 design intentionally provides at-least-once recovery and accepts that narrow duplicate-paper risk rather than silently losing the bill.

## API: `bcn_cashier_billing` POST `action=Pay`

Request:

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

1. Require Cashier, Restaurant Manager, Administrator, or System Manager.
2. Lock the Sales Order and ensure it is the unique active restaurant order for that customer/table.
3. If already submitted and Closed, resolve and return existing final documents instead of creating duplicates.
4. If Open, set Billing inside the payment transaction.
5. Validate tender rows and payment-mode company accounts.
6. Freeze Draft Sales Order totals and tax/service-charge state.
7. Set the in-memory Sales Order to Closed and submit it.
8. Create exactly one Sales Invoice from the Sales Order with `update_stock = 1`.
9. Preserve Sales Order linkage on Sales Invoice Items.
10. Validate final SI totals against the frozen Sales Order totals.
11. Submit the Sales Invoice.
12. Create one submitted Payment Entry per positive usable tender allocation.
13. Verify Sales Invoice outstanding is zero.
14. Return final identities.

Response:

```json
{
  "sales_order": "SAL-ORD-2026-00005",
  "sales_invoice": "ACC-SINV-2026-00001",
  "payment_entries": ["ACC-PAY-2026-00001"],
  "change_amount": 0,
  "duplicate": false
}
```

A retry after a successful commit returns the same SO/SI/PE identities with `duplicate = true`.

## Print and Payment Are Loosely Coupled

```text
Print Pending     -> Payment allowed
Print Processing  -> Payment allowed
Print Printed     -> Payment allowed
Print Failed      -> Payment allowed
```

Printer failure is not payment failure.

If payment completes while a snapshot is Pending/Processing, that snapshot remains valid and may print afterward. Payment does not delete or cancel old print jobs.

## Payment Validation

- At least one positive tender is required.
- Every tender must use an allowed DMT Mode of Payment with a usable company account.
- Non-cash tender may not exceed the remaining amount due.
- Cash may exceed the remaining amount; excess becomes `change_amount`.
- Overpayment is valid only through Cash.
- Each Payment Entry allocates at most the remaining invoice amount.

Example:

```text
Amount due: 10,500
Kpay tender: 5,500 -> PE allocation 5,500
Cash tender: 6,000 -> PE allocation 5,000
Change: 1,000
```

## Stock Handling

```text
Sales Invoice
update_stock = 1
```

No Delivery Note is created. Stock reduces when the Sales Invoice is submitted.

## Tax and Service Charge Consistency

`bcn_mobile_create_order` must apply the DMT selling/tax configuration to a newly created Draft Sales Order and preserve/recalculate the same tax rows when later waiter rounds modify the order.

Required equality, within normal currency rounding tolerance:

```text
Billing SO Net Total               == Final SI Net Total
Billing SO Total Taxes and Charges == Final SI Total Taxes and Charges
Billing SO Grand Total             == Final SI Grand Total
```

Mismatch blocks payment and rolls back finalization.

## Payment Idempotency

The Sales Order is locked during finalization.

Standard Sales Invoice Item -> Sales Order linkage is the finalization identity:

```text
exactly 1 submitted linked SI -> reuse it
0 submitted linked SI         -> inconsistent finalization error
>1 submitted linked SI        -> conflict error
```

Submitted Payment Entries are resolved through their Payment Entry Reference rows for that Sales Invoice.

No new custom idempotency field is required.

## Transaction Boundaries

### Print request

These commit together:

```text
SO validation
+ snapshot render/encode
+ new Pending BCN Print Job
+ Open -> Billing when applicable
```

### Claim

Job selection and Pending -> Processing claim metadata update occur under row lock in one request transaction.

### Result

Ownership validation and Processing -> Printed/Failed update occur in one request transaction. Same-terminal retry is idempotent.

### Payment

The following are one request/database transaction:

```text
validation
-> SO Closed + submit
-> SI create/validate/submit
-> PE create/submit
-> outstanding = 0 validation
```

Any failure rolls back to the externally visible pre-request state.

## Flutter Cashier Model and UI

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

### Open card

```text
Status: Open
Actions: Print Bill | Payment
```

### Billing card

```text
Status: Billing
Last Print: Pending / Processing / Printed / Failed
Actions: Reprint Bill | Payment
```

### Payment success

- Active bill card disappears.
- Cashier provider refreshes.
- Dine In and Takeaway providers refresh.
- Table becomes Available.
- The immediate payment-success UI retains a `Reprint Bill` action using the just-finalized `sales_order`; this action calls the submitted-Closed reprint behavior and copies the original snapshot. It does not create a Sales Invoice print.
- Once the success UI is dismissed, v1 does not add a new historical paid-bills browser; historical reprints outside that immediate flow can be handled by manager/support tooling.

### Failed print

Show a short cashier-friendly Failed state. Preserve the exact Windows error in `BCN Print Job.error_message`.

## Windows Printer Client

Cashier transport changes from realtime Socket.IO delivery to token-authenticated HTTP polling. Existing legacy Socket.IO listeners may remain for unrelated legacy/kitchen printing and must not be broken merely to add cashier polling.

Cashier polling flow:

```text
Startup
-> load config
-> detect installed local printer names
-> every 2 seconds POST bcn_print_jobs
-> job=null: wait
-> job: decode pdf_base64
-> use existing SumatraPDF silent-print path
-> POST Printed or Failed result
-> only then intentionally claim the next job
```

Required config:

```text
FRAPPE_BASE_URL
API_KEY
API_SECRET
POLL_INTERVAL_SECONDS = 2
SUMATRA_PDF_PATH
```

Cashier polling must not depend on login-cookie `AUTH_DATA`, although legacy Socket.IO code may continue using it if legacy mode remains enabled.

## Error Handling

Cashier-facing examples:

- Order no longer exists.
- Order is cancelled or in an invalid state.
- More than one active Draft Sales Order exists for the table.
- Waiter tries to modify a Billing order.
- DMT printer/print format is missing or invalid.
- PDF snapshot cannot be generated or encoded.
- Queue job cannot be created.
- Payment mode has no usable company account.
- Tender total is insufficient.
- Non-cash overpayment is rejected.
- SI totals do not match the frozen bill.
- Stock validation prevents SI submission.
- Closed SO has zero or multiple linked final Sales Invoices.

Printer-client examples:

- Missing BCN Printer Client role.
- Empty printer list.
- Job missing.
- Job not Processing and not an idempotent same-terminal retry.
- Job belongs to another printer API user.
- Unsupported terminal result.

## Expected Code Changes

### `HtayOoLwin/bcn-restaurant-mobile`

```text
server_scripts/mobile/create_order.py
server_scripts/mobile/cashier_billing.py
server_scripts/mobile/cashier_print_bill.py
server_scripts/mobile/print_jobs.py
server_scripts/mobile/print_job_result.py
docs/server-script-mobile.md

tests/test_ourcity_server_script_contract.py

mobile/bcn_restaurant_mobile/lib/features/cashier/data/cashier_repository.dart
mobile/bcn_restaurant_mobile/lib/features/cashier/domain/cashier_models.dart
mobile/bcn_restaurant_mobile/lib/features/cashier/presentation/cashier_screen.dart
mobile/bcn_restaurant_mobile/lib/features/printing/data/windows_print_repository.dart
mobile/bcn_restaurant_mobile/lib/features/printing/domain/cashier_bill_print_result.dart

mobile/bcn_restaurant_mobile/test/features/cashier/cashier_models_test.dart
mobile/bcn_restaurant_mobile/test/features/cashier/cashier_repository_test.dart
mobile/bcn_restaurant_mobile/test/features/cashier/cashier_screen_test.dart
mobile/bcn_restaurant_mobile/test/features/printing/windows_print_repository_test.dart
```

### `HtayOoLwin/local_printers_winapp`

Prefer a focused polling module called by the current app rather than growing one mixed-responsibility file.

Expected areas:

```text
polling client module
socket_app.py integration/legacy coexistence
printer_handlers.py only if needed for reusable single-PDF printing
config copy.json
polling tests
README.md
```

## OurCity Deployment Setup

```text
1. Create Custom DocType BCN Print Job with exact approved fields.
2. Create Role BCN Printer Client.
3. Create dedicated printer API user and assign the role.
4. Generate API Key/API Secret for that user.
5. Add DMT custom_cashier_printer.
6. Add DMT custom_cashier_print_format.
7. Deploy/update bcn_mobile_create_order.
8. Deploy bcn_cashier_billing.
9. Deploy bcn_cashier_print_bill.
10. Deploy bcn_print_jobs.
11. Deploy bcn_print_job_result.
12. Configure Windows base URL/token/poll interval/Sumatra path.
```

The `server_scripts/mobile/*.py` files are source-control mirrors. Git push does not deploy them to OurCity; the Server Script records must be updated on the site.

## Required Tests

### Server

- Active Open/Billing SO list.
- DMT tax/service-charge application/recalculation.
- Billing blocks waiter edits.
- Print creates Pending job.
- Open -> Billing only when job creation succeeds.
- Pending job stores correct SO snapshot/printer/format.
- Billing reprint creates a new job.
- Closed immediate reprint copies the previous snapshot and does not render SI.
- Claim role enforcement.
- Exact printer-name matching.
- Oldest matching Pending selection.
- `FOR UPDATE` claim locking.
- Pending -> Processing, owner/time, attempt increment.
- Stale Processing >60 seconds recovery.
- Result owner enforcement.
- Printed/Failed validation.
- Same-terminal result retry returns `duplicate=true`.
- Payment allowed for Pending/Processing/Printed/Failed print state.
- SI `update_stock = 1`.
- SO/SI total mismatch rollback.
- Split payment and cash change allocation.
- Payment idempotent retry resolution.

### Flutter

- Draft SO bill parsing.
- Last print status/job parsing.
- Open actions.
- Billing actions.
- Payment payload uses `sales_order` and tenders.
- Print/Reprint payload uses `sales_order`.
- Payment success refresh/removal.
- Immediate post-payment Reprint Bill action uses finalized SO name.

### Windows

- Exact token Authorization header.
- Local printer list claim request.
- 2-second configured default poll interval.
- `job=null` handling.
- Base64 PDF decode.
- Existing SumatraPDF print path.
- Printed result on success.
- Failed result with exact error on failure.
- Current result is reported before intentional next claim.
- Result retry after response timeout is safe.
- Legacy Socket.IO behavior is not accidentally broken.

## Acceptance Scenarios

### Happy path

```text
Table 01 waiter order
-> SO Open / table Occupied
-> Cashier Print Bill
-> Pending BCN Print Job + SO Billing
-> waiter edit rejected
-> Windows claims Processing
-> receipt prints
-> job Printed
-> Cashier Payment
-> SO Closed + submitted
-> one SI submitted with Update Stock = 1
-> PE(s) submitted
-> outstanding = 0
-> table Available
-> active cashier card disappears
```

### Printer offline/failure

```text
Print Bill
-> Pending job + SO Billing
-> printer unavailable / Failed
-> waiter remains locked
-> Payment still allowed
-> Reprint creates new Pending job
```

### Physical print then client crash

```text
Processing
-> paper prints
-> client crashes before result POST
-> >60 sec stale recovery
-> same snapshot may print again
```

This duplicate-paper risk is accepted for v1.

### Payment response timeout

```text
first Pay commits
-> client misses response
-> retry same SO
-> exactly one linked submitted SI found
-> existing PE(s) resolved
-> same identities returned with duplicate=true
```

### Print-result response timeout

```text
client POSTs Printed
-> server commits Printed
-> client misses response
-> client retries Printed
-> server returns duplicate=true
-> no state corruption
```

## Final Architecture

```text
Waiter
  -> one Open Draft SO per table

Cashier
  -> GET Open/Billing Draft SO bills
  -> Print/Reprint
       -> immutable SO PDF snapshot
       -> BCN Print Job Pending
       -> Open -> Billing when needed
  -> Payment
       -> SO Closed + submit
       -> SI Update Stock = 1
       -> PE(s)
       -> table Available

Windows Printer Client
  -> token-auth HTTP poll every ~2 seconds
  -> claim oldest matching Pending job
  -> Processing
  -> SumatraPDF silent print
  -> report Printed / Failed

OurCity
  -> Server Script API aliases only
  -> durable BCN Print Job queue
  -> no cashier realtime publish dependency
  -> no required custom-app installation
```
