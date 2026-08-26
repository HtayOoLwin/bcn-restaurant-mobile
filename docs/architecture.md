# BCN Restaurant Mobile Architecture

## Repository layout

The Git repository itself is a Frappe app repository:

```text
bcn-restaurant-mobile/
├── pyproject.toml
├── MANIFEST.in
├── bcn_restaurant/                # Frappe app package
│   ├── api/
│   ├── domain/
│   ├── events/
│   ├── services/
│   ├── bcn_restaurant/doctype/
│   ├── hooks.py
│   └── setup.py
├── mobile/
│   └── bcn_restaurant_mobile/     # Flutter client
├── tests/
└── docs/
```

This root layout is intentional: Bench and Frappe Cloud expect the app repository to expose `pyproject.toml` at the repository root.

## Runtime flow

```text
Flutter
  │
  │ HTTPS /api/method/...
  ▼
BCN Restaurant custom API
  │
  ├── Restaurant Settings
  ├── Restaurant Table Session
  ├── Item / Item Price
  ├── Kitchen Counter
  ▼
Sales Order (submitted KOT/order)
  │
  └── existing kitchen/cashier workflow
```

The mobile app never sends authoritative price, company, warehouse or kitchen counter values. The backend resolves these values from ERPNext.

## Phase 1

Implemented:
- Frappe session login
- role/bootstrap endpoint
- dine-in/takeaway table list
- menu and price endpoint
- cart with kitchen notes
- Restaurant Table Session creation/reuse
- idempotent Sales Order creation through `client_order_id`
- server-side kitchen routing

Deferred:
- kitchen queue/actions
- ready/served waiter flow
- consolidated billing
- payment/change
- Delivery Note auto-submit
- manager dashboard
- realtime events
