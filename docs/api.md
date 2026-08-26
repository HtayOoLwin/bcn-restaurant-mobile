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
