# Cashier Request-for-Bill Flow Design

Date: 2026-09-08

## Goal

Implement the restaurant billing lifecycle without installing a custom Frappe app on Frappe Cloud.

The required business flow is:

1. A waiter places an order and a Draft Sales Order is created.
2. The order appears on the Cashier screen immediately while it is still editable by the waiter.
3. The waiter presses **Request for Bill**.
4. A confirmation dialog warns that the order will be locked and cannot be edited after confirmation.
5. On confirmation, the Sales Order is submitted.
6. A Draft Sales Invoice is created from the submitted Sales Order using ERPNext standard Sales Order -> Sales Invoice mapping.
7. The Draft Sales Invoice is queued for automatic printing on the cashier printer.
8. The Cashier screen changes the order/bill state to **Bill Requested** and enables Payment.
9. When the cashier confirms payment, the Draft Sales Invoice is submitted, one or more Payment Entries are created/submitted for the selected tenders, and the table becomes Available.

## Constraints

- No custom Frappe app deployment on Frappe Cloud.
- Server-side behavior is implemented with Frappe Server Script API endpoints plus standard ERPNext documents/custom fields.
- Sales Orders remain Draft while the waiter is still ordering.
- After Request for Bill is confirmed, the waiter cannot add items, change qty, or change kitchen notes.
- Sales Invoice must be Draft when the bill is printed.
- Payment is disabled until the order reaches Bill Requested state.
- Auto print must not depend on the waiter tablet being connected directly to the cashier printer.

## State Model

Use hidden custom fields on Sales Order:

- `custom_mobile_billing_status` (Select, allow on submit)
  - `Ordering`
  - `Bill Requested`
  - `Paid`
- `custom_bill_requested_at` (Datetime, allow on submit)
- `custom_bill_requested_by` (Link/User, allow on submit)
- `custom_mobile_sales_invoice` (Link/Sales Invoice, allow on submit)

New Draft Sales Orders default to `Ordering`.

State transitions:

```text
Ordering
  -> Request for Bill confirmed
  -> Sales Order Submit
  -> Draft Sales Invoice Create
  -> Cashier Print Queue Create
  -> Bill Requested

Bill Requested
  -> Cashier Payment Confirm
  -> Sales Invoice Submit
  -> Payment Entry/Entries Submit
  -> Paid
  -> Table Available
```

There is no transition from `Bill Requested` back to `Ordering` in phase 1.

## Waiter UX

### Ordering

An open Draft Sales Order continues to behave as today. The waiter can:

- add new items;
- increase item qty;
- change permitted kitchen notes;
- place incremental orders.

### Request for Bill

For an open table/order, show a **Request for Bill** action.

Before calling the server, show a confirmation dialog:

**Title:** `Confirm Bill Request`

**Message:**

`Once you request the bill, this order will be locked. You cannot add or edit items after this. The bill will be printed automatically.`

Buttons:

- `Cancel`
- `Confirm & Print`

Cancel performs no mutation.

Confirm calls the request-bill API exactly once while the action is busy.

After success, refresh waiter tables/progress and prevent navigation into ordering for that Sales Order.

## Server API

### 1. Cashier Billing List

`GET /api/method/bcn_cashier_billing`

Returns both Draft Sales Orders in `Ordering` state and submitted Sales Orders in `Bill Requested` state that are not paid/closed.

Each bill row contains enough data for the Cashier screen without requiring a Sales Invoice in Ordering state:

- Sales Order name
- customer/table
- creation/modified time
- billing status
- totals/currency
- items/taxes required for display
- Draft Sales Invoice name when Bill Requested
- payment status
- cashier print status when available

Modes of Payment are returned in the same response.

### 2. Request for Bill

`POST /api/method/bcn_request_for_bill`

Input:

- `sales_order`

Server behavior is idempotent.

If the order is already Bill Requested and already has a linked Draft Sales Invoice, return the same result instead of creating another invoice or print job.

Validation:

- Sales Order exists;
- belongs to configured restaurant company;
- is Draft before first transition;
- billing status is `Ordering` before first transition;
- is not cancelled/paid;
- contains items;
- is not already linked to another active bill flow.

First transition:

1. Mark billing lock intent in the request transaction so stale/concurrent waiter updates are rejected.
2. Submit Sales Order.
3. Create Sales Invoice through ERPNext standard Sales Order -> Sales Invoice mapper.
4. Keep Sales Invoice in Draft.
5. Store Sales Invoice link, `Bill Requested` status, and audit values on Sales Order.
6. Create a durable Cashier Print Queue row for that Sales Invoice.
7. Return Sales Order + Draft Sales Invoice identifiers and billing status.

The endpoint must not call `frappe.db.commit()` manually. Database mutations remain in the normal Frappe request transaction so an exception before a successful response rolls the request back. If the client times out after the server committed successfully, a retry must detect and return the existing Bill Requested state, Draft Sales Invoice, and deterministic print queue rather than duplicate them.

### 3. Cashier Payment

`POST /api/method/bcn_cashier_billing`

Action: `Pay`

Input:

- `sales_order`
- `sales_invoice`
- `payments` as a list of `{mode_of_payment, amount}`

Validation:

- Sales Order is submitted and Bill Requested;
- linked Sales Invoice exists and is Draft;
- payment is not already completed;
- payment totals follow current Cash/Split rules;
- non-cash overpayment is rejected;
- cash overpayment may return change.

Transaction behavior:

1. Set the Draft Sales Invoice to `update_stock = 1`.
2. Submit Sales Invoice.
3. Create/submit Payment Entry per tender as required.
4. Mark Sales Order billing state `Paid`.
5. Return payment entry names and change amount.
6. Cashier/table refresh makes the table Available.

The payment operation must be retry-safe and must not create duplicate Sales Invoice submission or duplicate Payment Entries after a client timeout/retry.

## Waiter Lock Enforcement

UI lock is not sufficient. `bcn_mobile_create_order` must reject incremental order updates once the current Sales Order is no longer Draft or its billing status is not `Ordering`.

This server-side validation is mandatory so an old/stale waiter screen cannot modify a Bill Requested order.

## Cashier Screen

The Cashier screen is Sales-Order-centric before payment.

### Ordering card

- Shows Sales Order/table and current total.
- Status: `Ordering`.
- Payment button disabled.
- No manual Print Bill action in phase 1.

### Bill Requested card

- Shows Sales Order + Draft Sales Invoice number.
- Status: `Bill Requested`.
- Payment button enabled.
- Displays invoice totals used for payment.
- Shows auto-print state as `Queued`, `Printed`, or `Error` when available.

After successful payment the card disappears from the active cashier list and the table becomes Available.

## Auto Printing

Use the same durable Windows-worker pattern already used for kitchen printing rather than direct printing from the waiter tablet.

Introduce a `Cashier Print Queue` DocType with at least:

- Sales Invoice
- Sales Order
- printer name
- status (`Pending`, `Printing`, `Printed`, `Error`)
- attempts
- last error
- created/printed timestamps
- deterministic unique queue key

A single `Cashier Print Settings` record stores the exact Windows printer name.

`bcn_request_for_bill` creates the queue row only after the Draft Sales Invoice is successfully created.

The Windows worker:

1. polls Pending cashier jobs;
2. fetches the Draft Sales Invoice;
3. renders the cashier bill locally;
4. prints through the configured Windows printer;
5. marks the queue Printed or Error.

Queue key is deterministic from Sales Invoice name so API retry cannot create duplicate queue rows. The worker must claim/mark the durable job before printing so normal polling does not intentionally print the same completed job twice.

## Failure Handling

- If Sales Order submit, Sales Invoice creation, or initial queue creation raises before the request completes, the request transaction is allowed to roll back; no manual commit is used.
- If the HTTP client times out after a successful server commit, retry returns/reuses the existing Draft Sales Invoice and queue row.
- Printer offline/error does not roll back Sales Order/Sales Invoice; the durable queue remains Error/Pending for recovery.
- Payment cannot proceed unless the linked Draft Sales Invoice exists.
- Payment retry after an uncertain client result checks document state and existing payment references before creating anything new.

## Testing Strategy

TDD order:

1. Mobile contract test: Ordering bills appear in cashier list and Payment is disabled.
2. Mobile waiter test: Request for Bill shows confirmation; Cancel does nothing.
3. Mobile waiter test: Confirm calls request-bill endpoint and refreshes state.
4. Mobile test: Bill Requested prevents opening editable ordering flow.
5. Server-script contract tests/fixtures: request-bill idempotency and lock validation.
6. Server flow test: Sales Order Submit -> Draft Sales Invoice -> print queue.
7. Payment tests: Cash, non-cash, split, overpayment/change, duplicate retry.
8. Windows worker tests: one queue job -> one rendered/printed bill, retries do not duplicate.
9. Full Flutter tests + worker pytest + Python syntax verification before code review.

## Out of Scope for Phase 1

- Reopening/unlocking a Bill Requested order.
- Cancelling a submitted bill from mobile.
- Editing items after Request for Bill.
- Multiple active Sales Invoices for one Sales Order.
- Multiple cashier printers/routing rules.
