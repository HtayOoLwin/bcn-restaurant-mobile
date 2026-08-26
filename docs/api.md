# Phase 1 Mobile API

Base URL example:

```text
https://bcndemo-restaurant.nvi.frappe.cloud
```

All custom methods require an authenticated Frappe session.

## 1. Login

Uses the standard Frappe method:

```http
POST /api/method/login
Content-Type: application/x-www-form-urlencoded

usr=waiter@bcnrestaurant.com&pwd=<password>
```

The Flutter client stores only the returned `sid` cookie in secure storage.

## 2. Bootstrap

```http
GET /api/method/bcn_restaurant.api.bootstrap.get_bootstrap
```

Example response message:

```json
{
  "user": "waiter@bcnrestaurant.com",
  "full_name": "Waiter",
  "roles": ["Waiter"],
  "permissions": {
    "waiter": true,
    "kitchen": false,
    "cashier": false,
    "manager": false
  },
  "company": "BCN Restaurant",
  "currency": "MMK",
  "selling_price_list": "Restaurant Menu Price",
  "kitchen_counters": []
}
```

## 3. Tables / Takeaway Customers

```http
GET /api/method/bcn_restaurant.api.tables.get_tables?service_type=dine_in
```

`service_type` values:
- `dine_in`
- `takeaway`

Each row includes the current Open/Billing Restaurant Table Session when one exists.

## 4. Menu

```http
GET /api/method/bcn_restaurant.api.menu.get_menu
```

The server reads permitted POS item groups from `BCN Restaurant POS`, loads active menu Items and resolves the active rate from `Restaurant Menu Price`.

Example item:

```json
{
  "item_code": "FOOD-001",
  "item_name": "Chicken Fried Rice",
  "item_group": "Food Menu",
  "uom": "Plate",
  "rate": 8000.0,
  "currency": "MMK",
  "is_stock_item": false,
  "image": "/files/FOOD-001.jpg",
  "kitchen_counter": "Chinese Kitchen"
}
```

## 5. Create and Submit Order

```http
POST /api/method/bcn_restaurant.api.orders.create_order
Content-Type: application/x-www-form-urlencoded
```

Fields:

```text
customer=Table 01
session=RTS-2026-00001             # optional
client_order_id=<UUID v4>
remarks=Table requested less spicy # optional
items=[...]                        # JSON string
```

Example `items` JSON:

```json
[
  {
    "item_code": "FOOD-001",
    "qty": 2,
    "uom": "Plate",
    "kitchen_note": "No onion"
  },
  {
    "item_code": "COLD-001",
    "qty": 1,
    "uom": "Glass"
  }
]
```

The API ignores any client attempt to authoritatively choose rate, company, warehouse, kitchen counter or accounting fields because those values are not part of the accepted payload.

Example response:

```json
{
  "sales_order": "SAL-ORD-2026-00077",
  "session": "RTS-2026-00001",
  "grand_total": 19500.0,
  "preparation_summary": "New",
  "duplicate": false
}
```

If the same `client_order_id` is retried after a timeout, the API returns the already-created Sales Order with `duplicate: true` instead of creating a second order.

# Phase 2 Waiter + Kitchen API

All Phase 2 list endpoints operate only on submitted Sales Orders linked to a `Restaurant Table Session` whose status is `Open` or `Billing`. This prevents stale historical/unbilled Sales Orders from appearing in mobile operational queues.

## Kitchen Orders

```http
GET /api/method/bcn_restaurant.api.kitchen.get_orders
GET /api/method/bcn_restaurant.api.kitchen.get_orders?status=Preparing
```

Allowed status filters: `New`, `Accepted`, `Preparing`, `Ready`.

Kitchen users only receive rows whose `custom_kitchen_counter` is assigned to them through Kitchen Counter User Permission.

## Kitchen Item Action

```http
POST /api/method/bcn_restaurant.api.kitchen.update_item_status
Content-Type: application/x-www-form-urlencoded

item_row_name=<Sales Order Item row name>
action=Accept
```

Valid transitions:
- `New` + `Accept` -> `Accepted`
- `Accepted` + `Start Preparation` -> `Preparing`
- `Preparing` + `Mark Ready` -> `Ready`

When an item becomes Ready, prepared qty and ready timestamp are stored and the session waiter receives an in-app Notification Log.

## Waiter Order Progress

```http
GET /api/method/bcn_restaurant.api.waiter.get_order_progress
```

For normal Waiter users, only active sessions assigned to the logged-in waiter are returned. The response includes quantity counts and item-level status/note/counter information.

## Waiter Ready Queue

```http
GET /api/method/bcn_restaurant.api.waiter.get_ready_orders
```

Returns Ready items grouped by Sales Order/table. `can_serve_whole` is true only when at least one line is Ready and every other active line is already Ready or Served.

## Waiter Item Action

```http
POST /api/method/bcn_restaurant.api.waiter.item_action
Content-Type: application/x-www-form-urlencoded

item_row_name=<Sales Order Item row name>
action=Mark Served
```

Actions:
- `Mark Served` is allowed only from `Ready`.
- `Cancel` is allowed only from `New` and is blocked when a submitted Sales Invoice Item or Delivery Note Item already references the row.

## Serve Whole Order

```http
POST /api/method/bcn_restaurant.api.waiter.serve_whole_order
Content-Type: application/x-www-form-urlencoded

order_name=SAL-ORD-2026-00077
```

All remaining Ready rows become Served in one server-side operation. The endpoint rejects the request while any active item is `New`, `Accepted`, or `Preparing`.
