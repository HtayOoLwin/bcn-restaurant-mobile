# OurCity Mobile Server Scripts

Target site: **OurCity** (`https://ourcity.s.frappe.cloud`)

The restaurant mobile app talks to Frappe **Server Script API** aliases. A custom app installation is **not required** for these mobile API endpoints.

## API aliases

| Alias | Repository mirror | Current purpose |
| --- | --- | --- |
| `bcn_mobile_bootstrap` | `server_scripts/mobile/bootstrap.py` | Logged-in user, role flags, company/currency/price-list bootstrap |
| `bcn_mobile_tables` | `server_scripts/mobile/tables.py` | Dine In / Takeaway tables and Available / Occupied / Billing status |
| `bcn_mobile_menu` | `server_scripts/mobile/menu.py` | POS Profile DMT item groups, menu items and Standard Selling prices |
| `bcn_mobile_create_order` | `server_scripts/mobile/create_order.py` | Create/update one Open Draft Sales Order per table; reject ordering after Bill Request |
| `bcn_waiter_order_progress` | `server_scripts/mobile/waiter_order_progress.py` | List active Open Draft Sales Orders for the waiter Order Progress / Request for Bill screen |
| `bcn_request_for_bill` | `server_scripts/mobile/request_for_bill.py` | Waiter confirms bill request, submits Sales Order, creates Draft Sales Invoice and queues automatic cashier printing |
| `bcn_cashier_billing` | `server_scripts/mobile/cashier_billing.py` | List Ordering/Billing cards and complete Cash/Kpay/Split payment against the existing Draft Sales Invoice |
| `bcn_cashier_print_bill` | `server_scripts/mobile/cashier_print_bill.py` | Manual reprint after Bill Request using the linked Draft Sales Invoice snapshot |
| `bcn_print_jobs` | `server_scripts/mobile/print_jobs.py` | Windows printer client claims one Pending BCN Print Job |
| `bcn_print_job_result` | `server_scripts/mobile/print_job_result.py` | Windows printer client reports Printed/Failed result |

## Fixed OurCity values

```text
Company      = Doh Myot Daw BBQ & Restaurant
POS Profile  = DMT
Price List   = Standard Selling
Currency     = MMK
```

## Restaurant billing lifecycle

The operational state is kept in `Sales Order.custom_restaurant_status` so the existing app design can remain unchanged:

```text
Open    = waiter is still ordering
Billing = Request for Bill confirmed; Sales Order submitted; Draft Sales Invoice exists
Closed  = cashier payment completed
```

The required flow is:

```text
Waiter places first order
-> Draft Sales Order / Open
-> Cashier card appears immediately
-> waiter may add more items
-> Waiter: Request for Bill
-> confirmation dialog: Cancel / Confirm & Print
-> Sales Order status becomes Billing and Sales Order is submitted
-> one Draft Sales Invoice is created from the submitted Sales Order
-> Draft Sales Invoice PDF is queued automatically to BCN Print Job
-> table stays Billing and ordering is locked
-> Cashier Payment becomes enabled
-> Cashier confirms Cash / Kpay / Split payment
-> existing Draft Sales Invoice is submitted with update_stock = 1
-> Payment Entry/Entries are submitted
-> Sales Order restaurant status becomes Closed
-> table becomes Available
```

`Request for Bill` is retry-safe. A repeat request for an already submitted Billing Sales Order reuses the existing linked Draft Sales Invoice. The first automatic print request uses deterministic request ID `bill-request|<Sales Order>` so an HTTP retry does not intentionally create a second initial print job.

## Waiter ordering and lock behavior

`bcn_mobile_create_order` keeps one Draft (`docstatus = 0`) Sales Order for each active table/customer while `custom_restaurant_status = Open`.

A later waiter order for the same table reuses that Draft Sales Order. Matching rows are identified by item code, UOM, kitchen note and kitchen counter, and the incoming quantity is added to the existing quantity.

`bcn_waiter_order_progress` reads those same Open Draft Sales Orders and returns the rows needed by the mobile Order Progress screen. This is the screen that exposes the Waiter `Request for Bill` action.

After `bcn_request_for_bill` submits that Sales Order and changes the restaurant status to `Billing`, the waiter order API also checks submitted Billing Sales Orders. New items are rejected with a Billing lock instead of accidentally creating a new Draft Sales Order for the same table.

Required existing custom fields:

```text
Sales Order
- custom_client_order_id
- custom_restaurant_status

Sales Order Item
- custom_kitchen_note
- custom_kitchen_counter
- custom_printed_qty

Item
- custom_kitchen_counter
```

`custom_kitchen_counter` is copied from Item to Sales Order Item so the order keeps a counter snapshot. `custom_printed_qty` remains available for kitchen delta-print tracking.

## Table status

`bcn_mobile_tables` derives status from the active Sales Order rather than Restaurant Table Session:

```text
No active Open/Billing SO -> Available
Open Draft SO             -> Occupied
Billing Submitted SO      -> Billing
```

The Flutter table screen displays Available in green, Occupied in red and Billing in blue. A Billing table cannot be opened into the editable menu/cart flow.

## Cashier behavior

The existing `bcn-restaurant-mobile-without-kitchen-monitor` Cashier screen layout and Windows print flow are preserved.

An `Open` Draft Sales Order is shown on Cashier immediately, but Print and Payment are disabled. After Waiter Request for Bill succeeds, the card is `Billing`; the automatic print job has already been queued and Cashier can use Reprint Bill or Payment.

`bcn_cashier_billing` does not create a second Sales Invoice during payment. It requires the submitted Billing Sales Order to have exactly one linked Draft Sales Invoice, validates its totals against the Sales Order, submits that invoice with `update_stock = 1`, creates Payment Entry/Entries, verifies outstanding is zero and then marks the Sales Order restaurant status `Closed`.

A retry after a completed payment detects the submitted linked Sales Invoice and existing Payment Entries and returns them instead of intentionally duplicating final documents.

## Cashier printing

The branch keeps the existing **BCN Print Job** / Windows printer client architecture.

On Waiter Request for Bill, the PDF bytes stored in the initial BCN Print Job are rendered from the **Draft Sales Invoice**. The queue record continues to use the Sales Order as its document key so the existing Cashier status lookup, Windows worker and Closed reprint flow stay compatible.

Printer name comes from `DMT.custom_cashier_printer`.

For Draft Sales Invoice print layout:

- if optional POS Profile field `custom_cashier_invoice_print_format` is configured, it must point to a Sales Invoice Print Format and that format is used;
- otherwise Frappe's default Sales Invoice print rendering is used.

`bcn_cashier_print_bill` is now a manual **reprint** endpoint for Billing/Closed orders. It no longer changes an Open Sales Order into Billing; the waiter Request-for-Bill API owns that transition.

## Deployment

Create or update each Frappe Server Script as **Script Type = API** and use the alias shown above as the API Method. Copy the matching repository mirror content into the Server Script body.

These files are mirrors for source control and review. Editing a mirror file in GitHub does not automatically deploy it to OurCity; the corresponding Server Script on the site must be updated separately.

For this billing change, make sure the live site has these aliases updated before end-to-end testing:

```text
bcn_mobile_tables
bcn_mobile_create_order
bcn_waiter_order_progress
bcn_request_for_bill
bcn_cashier_billing
bcn_cashier_print_bill
bcn_print_jobs
bcn_print_job_result
```
