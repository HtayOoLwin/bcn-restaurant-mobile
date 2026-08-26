# BCN Restaurant Mobile Phase 2 Waiter + Kitchen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver active-session Waiter progress/serve operations and counter-isolated Kitchen preparation operations in backend and Flutter.

**Architecture:** Keep Sales Order/Sales Order Item as the operational KOT. Centralize preparation state rules in pure domain helpers, persist changes through custom whitelisted APIs, and use active Restaurant Table Sessions as the mobile queue boundary.

**Tech Stack:** Frappe/ERPNext v16, Python 3.11+, pytest, Flutter/Dart, Dio, Riverpod, go_router.

**Spec:** `docs/superpowers/specs/2026-08-26-phase2-waiter-kitchen-design.md`

## Global Constraints
- Target ERPNext/Frappe major version: 16.
- Do not expose generic Sales Order Item writes to mobile.
- Kitchen users only mutate assigned Kitchen Counter rows.
- Waiter users only mutate orders in their own active sessions.
- Active mobile orders must belong to Restaurant Table Session status Open or Billing.
- Mutation endpoints use POST.
- Reuse existing preparation fields and statuses exactly.
- Realtime is deferred; Phase 2 uses refresh/polling.

---

### Task 1: Preparation Domain Rules
**Files:**
- Test: `tests/test_preparation.py`
- Create: `bcn_restaurant/domain/preparation.py`

**Interfaces:**
- `kitchen_next_status(current_status: str, action: str) -> str`
- `summarize_statuses(statuses: list[str]) -> dict`
- `can_serve_whole(statuses: list[str]) -> bool`

- [ ] Write failing tests for valid/invalid transitions and summary states.
- [ ] Run tests and confirm RED.
- [ ] Implement minimal pure domain functions.
- [ ] Run tests and confirm GREEN.
- [ ] Commit.

### Task 2: Preparation Persistence Service
**Files:**
- Create: `bcn_restaurant/services/preparation.py`
- Modify: `bcn_restaurant/events/sales_order.py`
- Test: `tests/test_api_contract.py`

**Interfaces:**
- `recalculate_sales_order(order_name: str) -> dict`
- `get_active_session_order_names(...) -> list[str]`
- `assert_active_restaurant_order(order_doc, ...)`

- [ ] Add contract tests first.
- [ ] Implement shared recalculation and active-session guards.
- [ ] Reuse shared summary logic in Sales Order routing hook.
- [ ] Run pytest.
- [ ] Commit.

### Task 3: Kitchen API
**Files:**
- Create: `bcn_restaurant/api/kitchen.py`
- Modify: `tests/test_api_contract.py`

**Interfaces:**
- GET `bcn_restaurant.api.kitchen.get_orders`
- POST `bcn_restaurant.api.kitchen.update_item_status`

- [ ] Add failing API contract tests.
- [ ] Implement counter-isolated active queue.
- [ ] Implement New/Accepted/Preparing transitions.
- [ ] Create waiter Notification Log once when row becomes Ready.
- [ ] Recalculate parent summary after mutation.
- [ ] Run pytest/compile.
- [ ] Commit.

### Task 4: Waiter API
**Files:**
- Create: `bcn_restaurant/api/waiter.py`
- Modify: `tests/test_api_contract.py`

**Interfaces:**
- GET `bcn_restaurant.api.waiter.get_order_progress`
- GET `bcn_restaurant.api.waiter.get_ready_orders`
- POST `bcn_restaurant.api.waiter.item_action`
- POST `bcn_restaurant.api.waiter.serve_whole_order`

- [ ] Add failing API contract tests.
- [ ] Implement current-waiter active-session progress.
- [ ] Implement Ready queue and safe Serve actions.
- [ ] Implement New-only cancellation with billing/delivery guards.
- [ ] Recalculate/cancel parent as appropriate.
- [ ] Run pytest/compile.
- [ ] Commit.

### Task 5: Flutter Kitchen Feature
**Files:**
- Create: `mobile/bcn_restaurant_mobile/lib/features/kitchen/...`
- Modify: `mobile/bcn_restaurant_mobile/lib/core/router/app_router.dart`
- Test: `mobile/bcn_restaurant_mobile/test/kitchen_models_test.dart`

**Interfaces:**
- Kitchen repository consumes Phase 2 Kitchen API.
- Kitchen screen supports status filtering and context-valid action buttons.

- [ ] Add model/action mapping test.
- [ ] Implement models/repository/providers.
- [ ] Implement Kitchen Orders screen with refresh/polling.
- [ ] Route Kitchen-only login to `/kitchen`.
- [ ] Format/analyze/test when Flutter SDK available.
- [ ] Commit.

### Task 6: Flutter Waiter Progress + Ready Feature
**Files:**
- Create: `mobile/bcn_restaurant_mobile/lib/features/waiter_progress/...`
- Modify: `mobile/bcn_restaurant_mobile/lib/features/waiter/presentation/waiter_tables_screen.dart`
- Modify: `mobile/bcn_restaurant_mobile/lib/core/router/app_router.dart`
- Test: `mobile/bcn_restaurant_mobile/test/waiter_progress_models_test.dart`

**Interfaces:**
- Ready and progress repositories consume Phase 2 Waiter API.
- Waiter table screen navigates to `/waiter/ready` and `/waiter/progress`.

- [ ] Add parsing tests.
- [ ] Implement progress/ready models and repository.
- [ ] Implement Ready screen and actions.
- [ ] Implement Progress screen and New-item cancellation.
- [ ] Add 10-second polling and pull-to-refresh.
- [ ] Format/analyze/test when Flutter SDK available.
- [ ] Commit.

### Task 7: Docs + Verification + Package
**Files:**
- Modify: `docs/api.md`
- Modify: `docs/architecture.md`
- Modify: `README.md`

- [ ] Document new endpoints/state transitions.
- [ ] Run full backend pytest.
- [ ] Run Python compileall.
- [ ] Run Flutter checks when SDK available and report limitation otherwise.
- [ ] Produce updated ZIP/bundle/apply script for the user's Windows repo.
- [ ] Commit.
