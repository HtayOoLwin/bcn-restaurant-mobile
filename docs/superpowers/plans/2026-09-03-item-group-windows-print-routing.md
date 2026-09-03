# Item-Group Windows Print Routing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Kitchen Monitor and Android direct-print paths with durable ERPNext-managed Item Group routing to Windows kitchen and cashier printers.

**Architecture:** ERPNext persists idempotent print jobs, then uses Socket.IO only as a wake-up notification. The Windows middleware atomically claims jobs, prints them, and acknowledges success or failure; the Flutter app submits orders and requests manual cashier prints without connecting to printers.

**Tech Stack:** Frappe/ERPNext v16, Python 3.10+, Flutter/Dart 3.12+, Riverpod, GoRouter, Socket.IO, Windows printing.

**Spec:** `docs/superpowers/specs/2026-09-03-item-group-windows-print-routing-design.md`

## Global Constraints

- Kitchen printing starts only on `Sales Order.on_submit`.
- Authorized ERPNext cancellation starts a Cancel ticket; Waiters cannot cancel.
- Unmapped items route to one default kitchen printer per POS Profile.
- Cashier printing starts only when the cashier presses **Print Bill**.
- Android Bluetooth/direct printing is removed after the Windows path passes integration tests.
- Automatic attempts stop at three; an authorized manual retry may requeue a Failed job.
- Successful Kitchen and Cancel jobs must be idempotent.
- Socket.IO delivery is not proof of printing; only middleware acknowledgement marks Success.
- Deployment spans `HtayOoLwin/bcn-restaurant-mobile`, `waiminn/local_printers` (or an authorized fork), and the `local_printers_winapp_code` source.
- Do not begin destructive Kitchen/Flutter removal until Tasks 1–5 pass in a test environment.

---

## File Map

### Local Printers Frappe app

- Modify: `local_printers/hooks.py` — register narrow Sales Order hooks.
- Modify: `local_printers/utils.py` — compatibility wrappers only; move new responsibilities out.
- Modify: `local_printers/local_printers/doctype/printer_item_group/printer_item_group.json` — add Enabled and default-printer fields and trigger choices.
- Modify: `local_printers/local_printers/doctype/printer_item_group/printer_item_group.py` — validate configuration invariants.
- Create: `local_printers/local_printers/doctype/local_print_job/local_print_job.json`
- Create: `local_printers/local_printers/doctype/local_print_job/local_print_job.py`
- Create: `local_printers/printing/routing.py` — pure Item Group routing.
- Create: `local_printers/printing/jobs.py` — idempotent creation and job state transitions.
- Create: `local_printers/api/print_jobs.py` — claim, acknowledge, retry, status, test-print APIs.
- Test: `local_printers/tests/test_printer_config.py`
- Test: `local_printers/tests/test_print_routing.py`
- Test: `local_printers/tests/test_print_jobs.py`
- Test: `local_printers/tests/test_print_job_api.py`

### BCN Restaurant Frappe/Flutter app

- Modify: `bcn_restaurant/hooks.py` — remove Kitchen Monitor event dependencies after Local Printers hooks own printing.
- Create: `bcn_restaurant/api/printing.py` — restaurant-facing cashier/status/retry API facade.
- Modify: `bcn_restaurant/api/bootstrap.py` and `bcn_restaurant/domain/roles.py` — remove mobile Kitchen destination and expose print permissions/status.
- Modify: `mobile/bcn_restaurant_mobile/lib/core/router/app_router.dart` — remove `/kitchen`.
- Modify: `mobile/bcn_restaurant_mobile/lib/features/cashier/presentation/cashier_screen.dart` — call server print API.
- Create: `mobile/bcn_restaurant_mobile/lib/features/printing/data/windows_print_repository.dart`
- Create: `mobile/bcn_restaurant_mobile/lib/features/printing/domain/windows_print_status.dart`
- Modify: `mobile/bcn_restaurant_mobile/lib/features/printing/presentation/printer_settings_screen.dart` — show middleware/job status.
- Modify navigation files found by `rg "(/kitchen|Kitchen|kitchenNewOrderCountProvider)" mobile/bcn_restaurant_mobile/lib`.
- Delete Kitchen/direct-print files only after `rg` proves no references.
- Modify: `mobile/bcn_restaurant_mobile/pubspec.yaml` and Android manifest — remove unused direct-print dependencies/permissions.
- Test: backend tests under `tests/`; Flutter tests under `mobile/bcn_restaurant_mobile/test/`.

### Windows middleware

- Modify: `socket_app.py` — wake on Socket.IO and drain durable jobs.
- Create: `print_job_client.py` — claim/acknowledge REST client.
- Test: `tests/test_print_job_client.py`
- Test: `tests/test_socket_app.py`

---

### Task 1: Extend Printer Configuration

**Files:**
- Modify: `local_printers/local_printers/doctype/printer_item_group/printer_item_group.json`
- Modify/Create: `local_printers/local_printers/doctype/printer_item_group/printer_item_group.py`
- Test: `local_printers/tests/test_printer_config.py`

**Interfaces:**
- Produces configuration fields `enabled: Check` and `is_default_kitchen: Check`.
- Produces validation: at most one enabled default per `pos_profile`.
- Extends `trigger_method` values to `on_submit\non_cancel\nmanual`.

- [ ] **Step 1: Write failing configuration tests**

Add tests proving duplicate defaults are rejected and cashier/default combinations are rejected:

```python
def test_only_one_enabled_default_kitchen_printer(site):
    first = make_printer_config(pos_profile="Restaurant", is_default_kitchen=1)
    first.insert()
    second = make_printer_config(pos_profile="Restaurant", is_default_kitchen=1)
    with pytest.raises(frappe.ValidationError):
        second.insert()

def test_cashier_cannot_be_default_kitchen(site):
    config = make_printer_config(
        target_doctype="Sales Invoice",
        trigger_method="manual",
        is_cashier=1,
        is_default_kitchen=1,
    )
    with pytest.raises(frappe.ValidationError):
        config.insert()
```

- [ ] **Step 2: Run tests and confirm failure**

Run: `bench --site bcn-mobile.s.frappe.cloud run-tests --app local_printers --module local_printers.tests.test_printer_config`  
Expected: FAIL because the fields/validation do not exist.

- [ ] **Step 3: Add schema fields and validation**

Implement `validate()` so disabled records are ignored, defaults require `Sales Order` and non-cashier configuration, and a second enabled default for the same POS Profile throws a clear message.

- [ ] **Step 4: Run tests and migrate**

Run:
```bash
bench --site bcn-mobile.s.frappe.cloud migrate
bench --site bcn-mobile.s.frappe.cloud run-tests --app local_printers --module local_printers.tests.test_printer_config
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add local_printers/local_printers/doctype/printer_item_group local_printers/tests/test_printer_config.py
git commit -m "feat: validate default kitchen printer configuration"
```

### Task 2: Add Durable Local Print Job

**Files:**
- Create: `local_printers/local_printers/doctype/local_print_job/__init__.py`
- Create: `local_printers/local_printers/doctype/local_print_job/local_print_job.json`
- Create: `local_printers/local_printers/doctype/local_print_job/local_print_job.py`
- Create: `local_printers/printing/__init__.py`
- Create: `local_printers/printing/jobs.py`
- Test: `local_printers/tests/test_print_jobs.py`

**Interfaces:**
- Produces `create_print_job(*, source_doc, printer, ticket_type, print_format, payload, event_key=None) -> Document`.
- Produces `claim_next_jobs(worker_id: str, limit: int) -> list[dict]`.
- Produces `acknowledge_job(job_id: str, worker_id: str, success: bool, error: str | None) -> dict`.
- Statuses: Pending, Printing, Success, Failed.

- [ ] **Step 1: Write failing job lifecycle tests**

Test deterministic Kitchen/Cancel keys, unique manual Cashier keys, atomic claim, Success acknowledgement, and failure at attempt 3.

```python
def test_successful_event_job_is_idempotent(site):
    first = create_print_job(source_doc=order, printer="Kitchen-1", ticket_type="Kitchen", print_format="Kitchen", payload=b"x", event_key="Sales Order/SO-1/Kitchen-1/on_submit")
    second = create_print_job(source_doc=order, printer="Kitchen-1", ticket_type="Kitchen", print_format="Kitchen", payload=b"x", event_key="Sales Order/SO-1/Kitchen-1/on_submit")
    assert first.name == second.name
```

- [ ] **Step 2: Run tests and confirm failure**

Expected: FAIL because `Local Print Job` and job functions are missing.

- [ ] **Step 3: Implement DocType and state transitions**

Store payload as an Attach/Long Text representation suitable for current PDF size. Give `event_key` a unique index. Claim jobs using a database lock/conditional update; increment `attempt_count` only when claimed. Reject acknowledgements from a different worker.

- [ ] **Step 4: Run job tests and migrate**

Expected: all lifecycle tests PASS.

- [ ] **Step 5: Commit**

```bash
git add local_printers/printing local_printers/local_printers/doctype/local_print_job local_printers/tests/test_print_jobs.py
git commit -m "feat: persist idempotent local print jobs"
```

### Task 3: Implement Item Group Routing and Event Jobs

**Files:**
- Create: `local_printers/printing/routing.py`
- Modify: `local_printers/utils.py`
- Modify: `local_printers/hooks.py`
- Test: `local_printers/tests/test_print_routing.py`

**Interfaces:**
- Produces `route_order_items(doc, trigger_method: str) -> list[PrinterRoute]`.
- `PrinterRoute` contains `printer`, `print_format`, `no_letterhead`, and exact source row names.
- Consumes `create_print_job(...)` from Task 2.

- [ ] **Step 1: Write failing routing tests**

Cover two mapped Item Groups, mixed mapped/unmapped rows, default fallback, missing-default warning, and cancellation using recorded original routes.

- [ ] **Step 2: Run routing tests and confirm failure**

Expected: FAIL because routing module is absent.

- [ ] **Step 3: Implement pure routing**

Read each Item Group in one bulk query, build printer mappings once, route exact child-row names, and put only unmatched rows in the default route. Render filtered copies without mutating the persisted source document.

- [ ] **Step 4: Register narrow hooks**

Use:

```python
doc_events = {
    "Sales Order": {
        "on_submit": "local_printers.printing.routing.on_sales_order_submit",
        "on_cancel": "local_printers.printing.routing.on_sales_order_cancel",
    }
}
```

Remove the wildcard hook after confirming no supported document relies on it. The handlers create durable jobs then publish `document_print_event` after commit.

- [ ] **Step 5: Run tests**

Expected: routing and existing Local Printers tests PASS.

- [ ] **Step 6: Commit**

```bash
git add local_printers/hooks.py local_printers/utils.py local_printers/printing/routing.py local_printers/tests/test_print_routing.py
git commit -m "feat: route sales orders to item-group printers"
```

### Task 4: Add Job Claim, Acknowledgement, Retry, and Status APIs

**Files:**
- Create: `local_printers/api/__init__.py`
- Create: `local_printers/api/print_jobs.py`
- Test: `local_printers/tests/test_print_job_api.py`

**Interfaces:**
- `claim_jobs(worker_id: str, limit: int = 10) -> {"jobs": list}`
- `acknowledge(job_id: str, worker_id: str, success: int, error: str | None = None) -> {"status": str}`
- `retry_failed(job_id: str) -> {"status": "Pending"}`
- `get_status(pos_profile: str) -> {"online": bool, "last_seen": str | None, "pending": int, "failed": int}`

- [ ] **Step 1: Write failing API permission and transition tests**

Verify middleware role can claim/acknowledge, Cashier cannot claim, Manager can retry, Waiter cannot retry, and attempt count cannot exceed three automatically.

- [ ] **Step 2: Run tests and confirm failure**

Expected: endpoint import or permission assertions fail.

- [ ] **Step 3: Implement whitelisted authenticated endpoints**

Require a dedicated `Local Printer Worker` role for claim/acknowledge and Restaurant Manager/System Manager for retry. Update worker heartbeat on claim.

- [ ] **Step 4: Run tests**

Expected: API and lifecycle suites PASS.

- [ ] **Step 5: Commit**

```bash
git add local_printers/api/print_jobs.py local_printers/tests/test_print_job_api.py
git commit -m "feat: expose durable print worker APIs"
```

### Task 5: Upgrade Windows Middleware

**Files:**
- Create: `print_job_client.py`
- Modify: `socket_app.py`
- Create: `tests/test_print_job_client.py`
- Create: `tests/test_socket_app.py`

**Interfaces:**
- `PrintJobClient.claim(limit=10) -> list[PrintJob]`
- `PrintJobClient.acknowledge(job_id, success, error=None) -> None`
- `drain_pending_jobs() -> None`

- [ ] **Step 1: Write failing client tests**

Mock HTTP and printer execution. Assert Socket.IO only wakes the drain loop, reconnect drains missed jobs, success is acknowledged after the spool call, failure includes the printer error, and duplicate wake events do not run parallel drains.

- [ ] **Step 2: Run tests and confirm failure**

Run: `.\.venv\Scripts\python.exe -m pytest -q`  
Expected: FAIL because the durable client is absent.

- [ ] **Step 3: Implement REST job client**

Implement the printer execution adapter inside `socket_app.py` using its existing Windows print call. Reuse the authenticated session/config already used by `socket_app.py`. Deserialize `job_id`, `printer`, `payload`, `ticket_type`, and `attempt_count`. Never log credentials or full base64 payloads.

- [ ] **Step 4: Change Socket.IO handling**

On connect and `document_print_event`, trigger a single guarded `drain_pending_jobs()`. Claim jobs, print by exact Windows name, acknowledge each result, and continue processing other jobs after one failure.

- [ ] **Step 5: Run tests and a test-printer smoke test**

Expected: unit tests PASS; one test job transitions Pending → Printing → Success.

- [ ] **Step 6: Commit to the authorized Windows middleware repository**

```bash
git add socket_app.py print_job_client.py tests
git commit -m "feat: claim and acknowledge durable print jobs"
```

### Task 6: Add Restaurant-Facing Printing API

**Files:**
- Create: `bcn_restaurant/api/printing.py`
- Modify: `bcn_restaurant/api/bootstrap.py`
- Modify: `bcn_restaurant/domain/roles.py`
- Test: `tests/test_printing_api.py`
- Test: `tests/test_role_flags.py`

**Interfaces:**
- `request_cashier_bill(invoice_name: str) -> {"job_id": str, "status": str, "is_reprint": bool}`
- `get_print_status() -> {"online": bool, "last_seen": str | None, "pending": int, "failed": int}`
- `retry_print_job(job_id: str) -> {"status": str}`

- [ ] **Step 1: Write failing facade tests**

Assert Cashier may request a submitted accessible Sales Invoice, Waiter is rejected, no configuration returns a clear error without a job, repeat requests create distinct cashier jobs, and Waiter cannot cancel a Sales Order.

- [ ] **Step 2: Run tests and confirm failure**

Run: `pytest -q tests/test_printing_api.py tests/test_role_flags.py`  
Expected: FAIL because APIs/flags are missing.

- [ ] **Step 3: Implement minimal facade**

Delegate durable job operations to Local Printers APIs/services. Do not duplicate routing logic in BCN Restaurant. Return accepted job status, not a false claim that the physical print completed.

- [ ] **Step 4: Run backend tests**

Run: `pytest -q`  
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add bcn_restaurant/api/printing.py bcn_restaurant/api/bootstrap.py bcn_restaurant/domain/roles.py tests
git commit -m "feat: expose Windows printing to restaurant clients"
```

### Task 7: Move Cashier and Printer Status UI to Server Jobs

**Files:**
- Create: `mobile/bcn_restaurant_mobile/lib/features/printing/data/windows_print_repository.dart`
- Create: `mobile/bcn_restaurant_mobile/lib/features/printing/domain/windows_print_status.dart`
- Modify: `mobile/bcn_restaurant_mobile/lib/features/cashier/presentation/cashier_screen.dart`
- Modify: `mobile/bcn_restaurant_mobile/lib/features/printing/presentation/printer_settings_screen.dart`
- Test: `mobile/bcn_restaurant_mobile/test/features/printing/windows_print_repository_test.dart`
- Test: `mobile/bcn_restaurant_mobile/test/features/settings/settings_screen_test.dart`

**Interfaces:**
- `Future<PrintRequestResult> requestCashierBill(String invoiceName)`
- `Future<WindowsPrintStatus> getStatus()`
- `Future<void> retryJob(String jobId)`

- [ ] **Step 1: Write failing Flutter tests**

Assert Print Bill calls the server API exactly once, accepted response shows “Print job sent”, an API error is visible, and settings show online/last-seen/pending/failed plus authorized retry.

- [ ] **Step 2: Run tests and confirm failure**

Run: `flutter test test/features/printing test/features/settings/settings_screen_test.dart`  
Expected: FAIL because repository/models are absent and UI still calls direct printing.

- [ ] **Step 3: Implement repository and models**

Use the existing API client and Frappe response-unwrapping conventions. Keep status strings typed through an enum/value parser and preserve unknown status safely.

- [ ] **Step 4: Replace direct cashier printing**

Remove `CashierPrinterService.printBill` from the button flow. Show job acceptance separately from physical Success; invalidate status after request/retry.

- [ ] **Step 5: Replace Bluetooth settings UI**

Render service status, last seen, Pending/Failed counts, Retry Failed Jobs for authorized users, and Test Cashier Print. Do not show Bluetooth discovery/pairing controls.

- [ ] **Step 6: Run Flutter tests**

Expected: targeted tests PASS.

- [ ] **Step 7: Commit**

```bash
git add mobile/bcn_restaurant_mobile/lib/features/printing mobile/bcn_restaurant_mobile/lib/features/cashier mobile/bcn_restaurant_mobile/test/features
git commit -m "feat: route cashier printing through Windows jobs"
```

### Task 8: Remove Kitchen Monitor and Direct Android Printing

**Files:**
- Modify: `mobile/bcn_restaurant_mobile/lib/core/router/app_router.dart`
- Modify all files reported by the reference scans below.
- Delete only proven-unused files under `features/kitchen/` and direct-printer files.
- Modify: `mobile/bcn_restaurant_mobile/pubspec.yaml`
- Modify: Android manifest containing Bluetooth permissions.
- Test: `mobile/bcn_restaurant_mobile/test/router_without_kitchen_test.dart`
- Test: `tests/test_phase3_mobile_tooling.py`

**Interfaces:**
- Consumes working server print flow from Tasks 1–7.
- Produces no `/kitchen` route, Kitchen icon/badge/redirect, or Android printer connection.

- [ ] **Step 1: Inventory references**

Run:

```bash
rg -n "features/kitchen|/kitchen|KitchenOrdersScreen|kitchenNewOrderCountProvider|print_bluetooth_thermal|permission_handler|DirectPrinterService" mobile/bcn_restaurant_mobile
```

Record each reference and classify it as remove, replace, or retain. Check waiter-progress/ready features separately before deletion.

- [ ] **Step 2: Write failing absence tests**

Add router/widget tests proving authenticated roles never route to `/kitchen`, no Kitchen navigation action renders, and Waiter cancellation is absent.

- [ ] **Step 3: Run tests and confirm failure**

Expected: FAIL while Kitchen route/navigation exists.

- [ ] **Step 4: Remove routes, redirects, icons, badges, and providers**

Update router and all discovered callers. Remove Kitchen authorization as a mobile destination without weakening backend permission enforcement.

- [ ] **Step 5: Remove direct-print dependencies**

After `rg` shows no consumers, delete direct printer service/config UI code, remove `print_bluetooth_thermal`, remove `permission_handler` only if no other permission feature uses it, and remove unused Bluetooth manifest permissions.

- [ ] **Step 6: Run analyzer and full Flutter tests**

Run:

```bash
flutter pub get
dart format --set-exit-if-changed lib test
flutter analyze
flutter test
```

Expected: all commands PASS and reference scan returns no removed symbols.

- [ ] **Step 7: Commit**

```bash
git add mobile/bcn_restaurant_mobile tests
git commit -m "refactor: remove kitchen monitor and direct mobile printing"
```

### Task 9: End-to-End Verification and Deployment Documentation

**Files:**
- Create: `docs/item-group-windows-printing.md`
- Modify: `docs/install.md`
- Modify: `docs/phase3-android-e2e.md`

**Interfaces:**
- Documents exact deployment order, roles, printer mapping, Windows startup, troubleshooting, and rollback.

- [ ] **Step 1: Execute automated suites**

Run Local Printers bench tests, BCN backend `pytest -q`, Windows middleware `pytest -q`, Flutter analyzer, and Flutter tests. Save command outputs in the deployment record.

- [ ] **Step 2: Execute test-site matrix**

Verify:

1. Two mapped Item Groups produce one filtered ticket on each printer.
2. One unmapped item appears on the default printer.
3. Repeated Submit notification does not duplicate a successful ticket.
4. Manager cancellation prints a Cancel ticket to original printers.
5. Waiter cannot cancel.
6. Offline middleware leaves Pending jobs; reconnection prints them.
7. Printer failure stops automatic attempts at three; Manager retry works.
8. Cashier bill prints only after Print Bill.
9. Repeated Cashier print is treated as an intentional reprint.
10. Partial printer failure retries only the failed destination.

- [ ] **Step 3: Write operations guide**

Include exact POS Profile configuration, printer-name synchronization, default-printer validation, job statuses, retry procedure, Windows startup command/service configuration, and rollback order.

- [ ] **Step 4: Perform staged deployment**

Deploy in this order: Local Printers schema/API → printer mappings → Windows middleware → BCN backend → Flutter APK. Do not remove the old mobile build from devices until kitchen and cashier smoke tests pass.

- [ ] **Step 5: Final commits**

Commit docs in their owning repositories with:

```bash
git commit -m "docs: add Windows print routing operations guide"
```

- [ ] **Step 6: Final verification**

Confirm clean worktrees, record commit SHAs for all components, and verify the production POS Profile has exactly one enabled default kitchen printer.
