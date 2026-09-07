# OurCity Mobile Server Scripts

Target site: **OurCity** (`https://ourcity.s.frappe.cloud`)

The restaurant mobile app talks to Frappe **Server Script API** aliases. A custom app installation is **not required** for these mobile API endpoints.

## API aliases

| Alias | Repository mirror | Current purpose |
| --- | --- | --- |
| `bcn_mobile_bootstrap` | `server_scripts/mobile/bootstrap.py` | Logged-in user, role flags, company/currency/price-list bootstrap |
| `bcn_mobile_tables` | `server_scripts/mobile/tables.py` | Dine In / Takeaway tables and Available / Occupied / Billing status |
| `bcn_mobile_menu` | `server_scripts/mobile/menu.py` | POS Profile DMT item groups, menu items and Standard Selling prices |
| `bcn_mobile_create_order` | `server_scripts/mobile/create_order.py` | Create or update one Open Draft Sales Order per table |
| `bcn_cashier_billing` | deferred | Cashier flow is being redesigned for the Draft Sales Order workflow before its server-script mirror is committed |

## Fixed OurCity values

```text
Company      = Doh Myot Daw BBQ & Restaurant
POS Profile  = DMT
Price List   = Standard Selling
Currency     = MMK
```

## Draft restaurant order flow

`bcn_mobile_create_order` keeps one `Sales Order` in Draft (`docstatus = 0`) for each active table/customer where `custom_restaurant_status = Open`.

A later waiter order for the same table reuses that Draft Sales Order. Matching rows are identified by item code, UOM, kitchen note and kitchen counter. The new quantity is added to the existing quantity.

The Sales Order is **not submitted** by the waiter order API. If the active Draft Sales Order is already in `Billing`, the waiter API rejects new items so a second active order cannot be opened for the same table during checkout.

Required custom fields:

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

`custom_kitchen_counter` is copied from Item to Sales Order Item so the order keeps a counter snapshot. `custom_printed_qty` starts at `0` and is preserved when the same item row quantity increases. The next kitchen-print phase will use `qty - custom_printed_qty` as the print delta.

## Table status

`bcn_mobile_tables` derives table status from Draft Sales Orders rather than Restaurant Table Session:

```text
No Open/Billing Draft SO  -> Available
Open Draft SO             -> Occupied
Billing Draft SO          -> Billing
```

The Flutter table screen currently displays Available in green, Occupied in red and Billing in blue.

## Cashier note

The existing cashier mobile UI is still invoice-oriented. Do not copy the old `cashier_billing.py` into OurCity unchanged. The cashier phase must first reconcile the new flow:

```text
Open Draft Sales Order
-> Billing
-> submit Sales Order
-> create/submit Sales Invoice
-> payment
-> Closed
-> table becomes Available
```

Until that phase is implemented and verified, `bcn_cashier_billing` is documented here only as the Flutter alias that must be supported later.

## Deployment

Create or update each Frappe Server Script as **Script Type = API** and use the alias shown above as the API Method. Copy the matching repository mirror content into the Server Script body.

These files are mirrors for source control and review. Editing a mirror file in GitHub does not automatically deploy it to OurCity; the corresponding Server Script on the site must be updated separately.
