# Cashier Request-for-Bill Flow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement Draft Sales Order cashier visibility, waiter Request for Bill, submitted Sales Order -> Draft Sales Invoice billing, durable cashier auto-print, and cashier payment completion.

**Architecture:** Keep the current Server Script deployment model on Frappe Cloud. The Flutter app calls `bcn_request_for_bill` and `bcn_cashier_billing`; ERPNext standard mapping creates the Draft Sales Invoice only after Sales Order submit. Auto-print uses a durable Cashier Print Queue consumed by the Windows worker, not direct printing from the waiter tablet.

**Tech Stack:** ERPNext/Frappe v16 Server Script API, Python 3.x, pytest contract tests, Flutter/Dart, Dio, Riverpod, Windows Python print worker.

**Spec:** `docs/superpowers/specs/2026-09-08-cashier-request-bill-flow-design.md`

## Global Constraints
- No custom Frappe app deployment is required on the live Frappe Cloud site.
- Draft Sales Orders must appear on Cashier immediately.
- Request for Bill must show a confirmation dialog before mutation.
- Confirming Request for Bill submits the Sales Order, creates one Draft Sales Invoice, locks ordering, and queues one auto-print job.
- Payment is disabled while billing status is `Ordering` and enabled only for `Bill Requested`.
- Payment sets Sales Invoice `update_stock = 1`, submits it, creates/submits payments, and ends the active table order.
- Request-for-bill and payment actions must be retry-safe.
- Work remains on `feature/cashier-request-bill-flow`; do not merge `main` without explicit approval.

---

### Task 1: Server-Script Contracts and Site Setup Artifacts

**Files:**
- Create: `server_scripts/bcn_request_for_bill.py`
- Create: `server_scripts/bcn_cashier_billing.py`
- Create: `server_scripts/setup_cashier_billing.py`
- Create: `tests/test_cashier_server_script_contract.py`

**Interfaces:**
- POST `bcn_request_for_bill` with `sales_order`.
- GET/POST `bcn_cashier_billing`; POST action `Pay`.
- Sales Order fields: `custom_mobile_billing_status`, `custom_bill_requested_at`, `custom_bill_requested_by`, `custom_mobile_sales_invoice`.
- Queue DocType: `Cashier Print Queue`; settings singleton: `Cashier Print Settings`.

- [ ] Write failing source-contract tests for required endpoints, fields, standard Sales Invoice mapper, idempotency keys, and payment guards.
- [ ] Run pytest and confirm RED because the new artifacts do not exist.
- [ ] Add idempotent setup artifact for Custom Fields, Cashier Print Queue, and Cashier Print Settings.
- [ ] Add `bcn_request_for_bill` source: validate Draft Ordering SO, submit, standard-map Draft SI, store billing state, enqueue deterministic SI queue key; return existing state on retry.
- [ ] Add `bcn_cashier_billing` source: list Ordering/Bill Requested rows and handle retry-safe Pay.
- [ ] Run pytest and Python syntax verification; confirm GREEN.
- [ ] Commit.

### Task 2: Waiter Request-for-Bill Mobile Flow

**Files:**
- Modify: `mobile/bcn_restaurant_mobile/lib/features/waiter_progress/data/waiter_operations_repository.dart`
- Modify: `mobile/bcn_restaurant_mobile/lib/features/waiter_progress/domain/waiter_operation_models.dart`
- Modify: `mobile/bcn_restaurant_mobile/lib/features/waiter_progress/presentation/waiter_progress_screen.dart`
- Modify: `mobile/bcn_restaurant_mobile/lib/features/waiter/domain/table_models.dart`
- Modify: `mobile/bcn_restaurant_mobile/lib/features/waiter/presentation/waiter_tables_screen.dart`
- Test: `mobile/bcn_restaurant_mobile/test/waiter_progress_models_test.dart`
- Create: `tests/test_cashier_mobile_source_contract.py`

**Interfaces:**
- `WaiterOperationsRepository.requestBill(String salesOrder)` posts to `bcn_request_for_bill`.
- `WaiterProgressOrder.billingStatus` defaults to `Ordering`.
- Bill-requested tables/orders cannot navigate back into menu/cart editing.

- [ ] Add failing model/source tests for billing status, confirmation copy, and request-bill endpoint call.
- [ ] Confirm RED.
- [ ] Parse `billing_status` in waiter/table models.
- [ ] Add `Request for Bill` action on active Ordering progress cards.
- [ ] Show `Confirm Bill Request` dialog with `Cancel` and `Confirm & Print`.
- [ ] Disable duplicate taps while request is busy; refresh tables/progress/cashier after success.
- [ ] Block table ordering navigation when status is `Bill Requested`/submitted.
- [ ] Run available tests; commit.

### Task 3: Sales-Order-Centric Cashier Models and Repository

**Files:**
- Modify: `mobile/bcn_restaurant_mobile/lib/features/cashier/domain/cashier_models.dart`
- Modify: `mobile/bcn_restaurant_mobile/lib/features/cashier/data/cashier_repository.dart`
- Test: `tests/test_cashier_mobile_source_contract.py`
- Create/modify Dart model test under `mobile/bcn_restaurant_mobile/test/`.

**Interfaces:**
- `CashierBill` carries Sales Order, optional Draft Sales Invoice, billing status, print status, totals/items/taxes.
- `CashierBillingResponse.bills` replaces invoice-only active-list semantics.
- `paySplit` sends `sales_order`, `sales_invoice`, and tender list.

- [ ] Add failing parsing/source tests for Ordering SO without SI and Bill Requested SO with Draft SI.
- [ ] Confirm RED.
- [ ] Implement bill model while preserving payment-mode/tender models.
- [ ] Change repository payment payload to Sales Order + Sales Invoice contract.
- [ ] Run tests; commit.

### Task 4: Cashier Screen State Gating

**Files:**
- Modify: `mobile/bcn_restaurant_mobile/lib/features/cashier/presentation/cashier_screen.dart`
- Modify: `mobile/bcn_restaurant_mobile/lib/features/cashier/data/cashier_printer_service.dart` only if compatibility is needed for manual reprint.
- Test: `tests/test_cashier_mobile_source_contract.py`

**Interfaces:**
- Ordering card: visible, status `Ordering`, payment disabled.
- Bill Requested card: shows Draft SI, print status, payment enabled.
- Auto-print is server/worker-driven; no initial manual Print Bill requirement.

- [ ] Add failing source contract for `data.bills`, Ordering status, and payment gating.
- [ ] Confirm RED.
- [ ] Refactor list/search/card rendering from `invoices` to `bills`.
- [ ] Disable payment unless `bill.canPay`.
- [ ] Keep payment sheet split-payment behavior and invalidate table/cashier providers on success.
- [ ] Run tests; commit.

### Task 5: Cashier Windows Print Worker

**Repository:** `HtayOoLwin/local_printers_winapp`

**Files:**
- Create/modify cashier queue client, renderer, and worker integration alongside existing kitchen queue worker.
- Test with pytest before production changes.

**Interfaces:**
- Poll `Cashier Print Queue` Pending/Error-retry jobs.
- Fetch Draft Sales Invoice + items/taxes.
- Render local cashier bill and print to `Cashier Print Settings.printer_name`.
- Mark job Printed only after successful print.

- [ ] Create isolated feature branch in worker repo.
- [ ] Add failing worker tests for one SI -> one print and retry idempotency.
- [ ] Confirm RED.
- [ ] Implement queue poll/claim/render/print/status update.
- [ ] Run full worker pytest + py_compile; commit.

### Task 6: Live Deployment and End-to-End Verification

**Files:**
- Update docs with exact Server Script names/API methods and setup steps.

- [ ] Create/update Custom Fields/Queue/Settings on the ERPNext site using the setup artifact or equivalent site configuration.
- [ ] Create API Server Scripts `bcn_request_for_bill` and `bcn_cashier_billing` from committed source.
- [ ] Add the billing lock check to the live `bcn_mobile_create_order` script before it accepts an existing session update.
- [ ] Test Draft SO appears on Cashier immediately.
- [ ] Test Request for Bill confirmation Cancel performs no mutation.
- [ ] Test Confirm submits SO, creates exactly one Draft SI, locks waiter editing, and auto-prints once.
- [ ] Test Cash payment and Split payment; confirm SI submit/update-stock/payment/table Available.
- [ ] Retry Request for Bill and Pay after success; confirm no duplicate SI/queue/payment.
- [ ] Run Flutter analyze/test on the user's Windows workstation and worker full pytest/py_compile.
- [ ] Perform separate code review before any merge.
