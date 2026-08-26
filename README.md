# BCN Restaurant Mobile

A Frappe/ERPNext v16 custom app with a Flutter mobile client for BCN Restaurant.

The **repository root is intentionally the Frappe app root** so the GitHub repository can be installed by Bench/Frappe Cloud. The Flutter client lives under `mobile/bcn_restaurant_mobile`.

## Layout

- `bcn_restaurant/` — Frappe application package
- `pyproject.toml` — Frappe app package/dependency metadata
- `mobile/bcn_restaurant_mobile/` — Flutter mobile client
- `tests/` — fast backend tests that do not require a running bench
- `docs/` — architecture, API and installation guides

Phase 1 implements login, role bootstrap, dine-in/takeaway selection, menu, cart, and idempotent Sales Order creation/submission.

## Start here

1. Read `docs/install.md`.
2. Install the root Frappe app on a v16 test site.
3. Generate Android platform files in `mobile/bcn_restaurant_mobile`.
4. Run Flutter with the `BASE_URL` dart define.

Backend fast tests:

```bash
PYTHONPATH=. pytest -q tests
```
