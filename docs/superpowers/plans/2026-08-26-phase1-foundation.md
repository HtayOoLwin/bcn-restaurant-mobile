# BCN Restaurant Mobile Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a Git-ready Frappe v16 backend and Flutter Phase 1 waiter ordering flow from login through submitted Sales Order.

**Architecture:** Keep Sales Order as the KOT/order transaction and place a constrained custom API between Flutter and ERPNext. Add Restaurant Settings and Restaurant Table Session for configuration and visit grouping, and use a client UUID for idempotent order creation.

**Tech Stack:** Frappe/ERPNext v16, Python 3.11+, pytest, Flutter/Dart, Dio, Riverpod, go_router, flutter_secure_storage.

**Spec:** `docs/superpowers/specs/2026-08-26-phase1-mobile-design.md`

## Global Constraints
- Target ERPNext/Frappe major version: 16.
- Mobile must not call generic document insert/submit endpoints for order creation.
- Mobile must not send authoritative price, warehouse, kitchen counter, company, or accounting values.
- Passwords must never be persisted; only the Frappe SID session cookie may be stored securely.
- Sales Order remains the restaurant KOT/order transaction.
- Place-order retries must be idempotent through `custom_client_order_id`.
- Phase 1 excludes cashier, kitchen workflow screens, manager dashboard, realtime, and full offline ordering.

---

### Task 1: Repository and Frappe App Foundation

**Files:**
- Create: `.gitignore`
- Create: `README.md`
- Create: `pyproject.toml`
- Create: `bcn_restaurant/__init__.py`
- Create: `bcn_restaurant/hooks.py`
- Create: `bcn_restaurant/modules.txt`
- Create: `bcn_restaurant/patches.txt`

**Interfaces:**
- Produces installable Python package `bcn_restaurant` with Frappe hooks.

- [ ] Create the Frappe v16 package scaffold matching `bench new-app` layout.
- [ ] Add install/migration hooks and Sales Order routing hook registration.
- [ ] Document bench installation commands.
- [ ] Verify Python files compile.
- [ ] Commit `chore: scaffold frappe app`.

### Task 2: Domain Validation and Pricing Helpers

**Files:**
- Test: `tests/test_order_payload.py`
- Create: `bcn_restaurant/domain/order_payload.py`
- Create: `bcn_restaurant/domain/__init__.py`
- Create: `bcn_restaurant/services/menu.py`
- Create: `bcn_restaurant/services/__init__.py`

**Interfaces:**
- Produces `normalize_items(items) -> list[dict]` and `validate_client_order_id(value) -> str`.
- Produces server-side menu price lookup helper used by menu and orders APIs.

- [ ] Write failing pytest tests for UUID validation, positive qty, duplicate item preservation, and kitchen-note trimming.
- [ ] Run pytest and confirm RED.
- [ ] Implement minimal pure Python validation.
- [ ] Run pytest and confirm GREEN.
- [ ] Add Frappe price lookup service using Item Price validity and UOM.
- [ ] Compile Python files.
- [ ] Commit `feat: add order payload validation`.

### Task 3: Restaurant Settings, Table Session, and Custom Fields

**Files:**
- Create: `bcn_restaurant/bcn_restaurant/doctype/restaurant_settings/*`
- Create: `bcn_restaurant/bcn_restaurant/doctype/restaurant_table_session/*`
- Create: `bcn_restaurant/setup.py`
- Create: `bcn_restaurant/patches/v1_0/add_sales_order_fields.py`

**Interfaces:**
- Produces Single DocType `Restaurant Settings`.
- Produces DocType `Restaurant Table Session`.
- Produces Sales Order fields `custom_restaurant_session`, `custom_client_order_id`.

- [ ] Define Restaurant Settings JSON and Python controller.
- [ ] Define Restaurant Table Session JSON and Python controller.
- [ ] Implement custom-field creation with `create_custom_fields`.
- [ ] Wire `after_install` and patch entry.
- [ ] Compile all Python files.
- [ ] Commit `feat: add restaurant settings and sessions`.

### Task 4: Kitchen Routing Hook and Phase 1 APIs

**Files:**
- Create: `bcn_restaurant/api/__init__.py`
- Create: `bcn_restaurant/api/common.py`
- Create: `bcn_restaurant/api/bootstrap.py`
- Create: `bcn_restaurant/api/tables.py`
- Create: `bcn_restaurant/api/menu.py`
- Create: `bcn_restaurant/api/orders.py`
- Create: `bcn_restaurant/events/sales_order.py`

**Interfaces:**
- Produces whitelisted methods `get_bootstrap`, `get_tables`, `get_menu`, `create_order`.
- Produces `route_kitchen_items(doc, method=None)` for `Sales Order.before_validate`.

- [ ] Implement role checks and settings loader.
- [ ] Implement bootstrap response with role flags and counter permissions.
- [ ] Implement dine-in/takeaway table list with open-session state.
- [ ] Implement menu response with authoritative server-side price.
- [ ] Implement idempotent create-order transaction and session reuse/create.
- [ ] Implement kitchen routing from Item → Kitchen Counter → warehouse.
- [ ] Compile Python files.
- [ ] Commit `feat: add phase 1 restaurant APIs`.

### Task 5: Flutter Project Foundation and Authentication

**Files:**
- Create: `mobile/bcn_restaurant_mobile/pubspec.yaml`
- Create: `mobile/bcn_restaurant_mobile/lib/main.dart`
- Create: `mobile/bcn_restaurant_mobile/lib/app.dart`
- Create: `mobile/bcn_restaurant_mobile/lib/core/config/app_config.dart`
- Create: `mobile/bcn_restaurant_mobile/lib/core/network/api_client.dart`
- Create: `mobile/bcn_restaurant_mobile/lib/core/network/api_exception.dart`
- Create: `mobile/bcn_restaurant_mobile/lib/core/storage/session_storage.dart`
- Create: `mobile/bcn_restaurant_mobile/lib/features/auth/*`
- Create: `mobile/bcn_restaurant_mobile/lib/features/bootstrap/*`

**Interfaces:**
- Produces authenticated Dio client that persists only `sid`.
- Produces `AuthController` and bootstrap model.

- [ ] Define current stable package constraints compatible with current Flutter stable.
- [ ] Implement BASE_URL dart-define configuration.
- [ ] Implement SID cookie extraction/storage/interceptor.
- [ ] Implement login/logout and bootstrap repositories.
- [ ] Implement login screen and auth routing.
- [ ] Run `dart format`/`flutter analyze` when SDK available.
- [ ] Commit `feat: add flutter authentication foundation`.

### Task 6: Flutter Table, Menu, Cart, and Place Order Flow

**Files:**
- Create: `mobile/bcn_restaurant_mobile/lib/features/waiter/*`
- Create: `mobile/bcn_restaurant_mobile/lib/features/menu/*`
- Create: `mobile/bcn_restaurant_mobile/lib/features/cart/*`
- Create: `mobile/bcn_restaurant_mobile/lib/features/orders/*`
- Test: `mobile/bcn_restaurant_mobile/test/cart_controller_test.dart`

**Interfaces:**
- Consumes backend Phase 1 APIs.
- Produces end-to-end waiter flow: choose service type/table → menu → cart → create order.

- [ ] Write cart behavior test for add/increment/decrement/total.
- [ ] Implement immutable cart state and controller.
- [ ] Implement table/takeaway grid and table repository.
- [ ] Implement categorized menu and menu repository.
- [ ] Implement cart screen with per-line kitchen note.
- [ ] Generate UUID `client_order_id`, submit order, and show success/order name.
- [ ] Run Flutter tests/analyze when SDK available.
- [ ] Commit `feat: add waiter phase 1 ordering flow`.

### Task 7: Documentation and Verification

**Files:**
- Create: `docs/api.md`
- Create: `docs/install.md`
- Modify: `README.md`

**Interfaces:**
- Produces exact setup/run/deploy instructions for the user's Windows repo and Frappe bench.

- [ ] Document endpoints and payload examples.
- [ ] Document Windows Flutter run command with BASE_URL.
- [ ] Document Frappe app install/migrate steps.
- [ ] Run backend pytest and Python compileall.
- [ ] Run Flutter analyze/test if Flutter SDK exists; otherwise record the unverified environment limitation.
- [ ] Package repo content as a ZIP for transfer into the user's cloned repository.
- [ ] Commit `docs: add setup and api guide`.
