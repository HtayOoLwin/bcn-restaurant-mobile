# Cashier Polling Queue Server + Mobile Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the OurCity Server-Script-only cashier flow backed by Draft Sales Orders and a durable, request-idempotent `BCN Print Job` polling queue, including Flutter cashier UI/payment integration.

**Architecture:** Cashier billing remains Sales-Order-first. `bcn_cashier_print_bill` stores an immutable Draft Sales Order PDF snapshot in a Pending `BCN Print Job`; each intentional print uses a unique client `request_id`, and a transport retry reuses that same id so the server returns the existing job instead of creating a second one. Windows clients claim jobs through `bcn_print_jobs` and report results through `bcn_print_job_result`; stale Processing jobs time out to Failed and are never automatically requeued. Payment remains independent from print success and atomically submits the Sales Order, creates one Sales Invoice with `update_stock = 1`, creates Payment Entry records, and closes the restaurant order.

**Tech Stack:** ERPNext/Frappe v16 Server Script safe execution, Python `pytest` static contract tests, Flutter/Dart + Riverpod + Dio.

**Spec:** `docs/superpowers/specs/2026-09-07-cashier-draft-sales-order-billing-design.md`

## Global Constraints

- Target site is exactly `https://ourcity.s.frappe.cloud`.
- Target branch is exactly `bcn-restaurant-mobile-without-kitchen-monitor`; do not merge into `main` as part of this work.
- Company is exactly `Doh Myot Daw BBQ & Restaurant`.
- POS Profile is exactly `DMT`.
- Selling Price List is exactly `Standard Selling`.
- Currency is exactly `MMK`.
- Keep one active Draft Sales Order per table/customer visit.
- Restaurant states are exactly `Open`, `Billing`, `Closed` in `Sales Order.custom_restaurant_status`.
- Waiter APIs never submit Sales Orders.
- Billing freezes waiter changes.
- Cashier bill source is the Sales Order snapshot, never an early Sales Invoice.
- Payment creates one Sales Invoice with `update_stock = 1`; do not create a Delivery Note.
- Payment may succeed regardless of Pending/Processing/Printed/Failed print state.
- Do not require `bcn_restaurant` or `local_printers` custom apps on OurCity.
- Printer config comes from POS Profile `DMT.custom_cashier_printer` and `DMT.custom_cashier_print_format`.
- Printer-client APIs require role `BCN Printer Client`.
- Print result ownership is the authenticated ERPNext API user stored in `claimed_by`.
- `BCN Print Job.request_id` is unique and required for cashier print requests.
- Same intentional HTTP operation reuses the same `request_id`; intentional Reprint generates a new one.
- Stale Processing jobs older than 60 seconds become Failed with exact error `Print result unknown after client timeout`; never return them to Pending automatically.
- Reprint creates a new job; old jobs remain immutable audit history.
- Do not call `frappe.db.commit()` or `frappe.db.rollback()` inside Server Scripts.

---

## File Structure

- `server_scripts/mobile/create_order.py` — DMT tax template/totals on Draft Sales Orders.
- `server_scripts/mobile/cashier_billing.py` — GET Open/Billing Sales Order bills and POST payment finalization.
- `server_scripts/mobile/cashier_print_bill.py` — request-idempotent snapshot queue creation, Open -> Billing, Closed snapshot-copy reprint.
- `server_scripts/mobile/print_jobs.py` — stale timeout-to-Failed + one-job atomic claim.
- `server_scripts/mobile/print_job_result.py` — ownership-enforced Printed/Failed result with same-terminal retry safety.
- `tests/test_ourcity_server_script_contract.py` — source-control contract tests for aliases/invariants.
- `docs/server-script-mobile.md` — OurCity manual setup and deployment mapping.
- `mobile/bcn_restaurant_mobile/lib/features/cashier/domain/cashier_models.dart` — Sales-Order bill/payment models.
- `mobile/bcn_restaurant_mobile/lib/features/cashier/data/cashier_repository.dart` — GET bills and Pay by `sales_order`.
- `mobile/bcn_restaurant_mobile/lib/features/printing/domain/cashier_bill_print_result.dart` — queue response model including request id and duplicate flag.
- `mobile/bcn_restaurant_mobile/lib/features/printing/data/windows_print_repository.dart` — `bcn_cashier_print_bill` request with `sales_order` + `request_id`.
- `mobile/bcn_restaurant_mobile/lib/features/cashier/presentation/cashier_screen.dart` — Open/Billing actions, print status, payment, immediate post-payment reprint.
- Flutter tests under `mobile/bcn_restaurant_mobile/test/features/cashier/` and `.../printing/`.

---

## Completed Preflight Gate 0: Raw PDF Bytes -> Base64 in OurCity Safe Exec

- [x] Rendered Draft Sales Order `SAL-ORD-2026-00005` with `frappe.get_print(..., as_pdf=True)`.
- [x] Pure-Python base64 encoder returned a larger base64 payload whose prefix was `JVBERi0`.
- [x] Windows `[Convert]::FromBase64String(...)` decoded the response back to a `%PDF-` document.
- [x] Queue payload remains `pdf_base64`; no transport redesign is needed.

Use the proven pure-Python encoder inside `cashier_print_bill.py`. Do not call `frappe.utils.pdf_to_base64` with raw PDF bytes.

---

### Task 1: Keep Draft Sales Order Tax/Service-Charge Totals Stable — COMPLETE

**Implemented commits:**

```text
6ff414d test: require DMT tax recalculation for restaurant orders
486dbca feat: keep restaurant draft totals aligned with DMT taxes
46dc32d test: reject unsupported sales order set_taxes call
43df21a fix: load DMT taxes through whitelisted server API
```

- [x] RED observed.
- [x] Unsupported `sales_order.set_taxes()` was caught in code review.
- [x] Production source now loads tax rows through whitelisted `erpnext.accounts.services.taxes.get_taxes_and_charges` via `frappe.call` only when rows are missing.
- [x] `sales_order.calculate_taxes_and_totals()` runs before save.
- [x] Contract suite passed.
- [x] Separate review closed.

---

### Task 2: Add Cashier Bill List GET API — COMPLETE

**Implemented commits:**

```text
e9dbc37 test: require draft sales order cashier billing list
d77ba13 feat: list draft sales order bills for cashier
```

- [x] RED observed because `cashier_billing.py` did not exist.
- [x] GET lists only company-scoped Draft Sales Orders in Open/Billing.
- [x] GET returns item/tax rows and DMT payment modes.
- [x] GET reads latest print status/job when `BCN Print Job` exists.
- [x] GET does not freeze state or create accounting documents.
- [x] Contract suite passed with 8 tests.
- [x] Separate review closed.

---

### Task 3: Add Request-Idempotent Draft/Closed Cashier Print Queue Endpoint

**Files:**
- Create: `server_scripts/mobile/cashier_print_bill.py`
- Modify: `tests/test_ourcity_server_script_contract.py`

**Interfaces:**
- Consumes: `sales_order`, required `request_id`, DMT printer/print-format fields, `BCN Print Job`, proven pure-Python base64 encoder.
- Produces: first request -> new Pending job; same request retry -> existing job `duplicate=true`; Open -> Billing atomically; intentional Billing/Closed reprint uses a new request id/job.

- [ ] **Step 1: Add failing request-idempotency contract tests**

```python
def test_cashier_print_bill_requires_request_id_and_queues_snapshot():
    path = SERVER_SCRIPTS / "cashier_print_bill.py"
    assert path.exists()
    source = _read(path)
    assert 'request_id = (frappe.form_dict.get("request_id") or "").strip()' in source
    assert "request_id is required" in source
    assert 'frappe.db.exists("BCN Print Job", {"request_id": request_id})' in source
    assert 'job.request_id = request_id' in source
    assert 'job.status = "Pending"' in source
    assert 'sales_order.custom_restaurant_status = "Billing"' in source
    assert 'frappe.get_print(' in source
    assert '"Sales Order"' in source
    assert "pdf_base64" in source
    assert "publish_realtime" not in source
    assert "Sales Invoice" not in source


def test_cashier_print_bill_duplicate_request_returns_existing_job():
    source = _read(SERVER_SCRIPTS / "cashier_print_bill.py")
    assert '"duplicate": True' in source
    assert "Print request ID is already used for another document" in source


def test_cashier_print_bill_closed_reprint_copies_existing_snapshot():
    source = _read(SERVER_SCRIPTS / "cashier_print_bill.py")
    assert 'custom_restaurant_status == "Closed"' in source
    assert "No printable cashier snapshot exists" in source
    assert "previous_job.pdf_base64" in source
```

- [ ] **Step 2: Run RED**

```powershell
python -m pytest tests/test_ourcity_server_script_contract.py -k "cashier_print_bill" -q
```

Expected: FAIL because `cashier_print_bill.py` does not exist.

- [ ] **Step 3: Implement exact base64 helper proven by Gate 0**

Inside the standalone Server Script mirror define:

```python
def encode_pdf_base64(pdf):
    alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    out = []
    i = 0
    length = len(pdf)
    while i < length:
        b0 = pdf[i]
        has_b1 = i + 1 < length
        has_b2 = i + 2 < length
        b1 = pdf[i + 1] if has_b1 else 0
        b2 = pdf[i + 2] if has_b2 else 0
        triple = (b0 << 16) | (b1 << 8) | b2
        out.append(alphabet[(triple >> 18) & 63])
        out.append(alphabet[(triple >> 12) & 63])
        out.append(alphabet[(triple >> 6) & 63] if has_b1 else "=")
        out.append(alphabet[triple & 63] if has_b2 else "=")
        i += 3
    return "".join(out)
```

- [ ] **Step 4: Implement auth + early request-idempotency check**

Require Cashier, Restaurant Manager, System Manager, or Administrator. Parse:

```python
sales_order_name = (frappe.form_dict.get("sales_order") or "").strip()
request_id = (frappe.form_dict.get("request_id") or "").strip()
```

Throw if either is blank. Then check `BCN Print Job` by `request_id` before rendering. If found, load it and require `document_type == "Sales Order"` and `document_name == sales_order_name`. Return:

```python
frappe.response["message"] = {
    "sales_order": sales_order_name,
    "request_id": request_id,
    "print_job": existing_job.name,
    "status": existing_job.status,
    "is_reprint": False,
    "duplicate": True,
}
```

If the same id belongs to another document, throw `Print request ID is already used for another document`.

- [ ] **Step 5: Implement Draft Open/Billing new-request path**

Lock exact SO name:

```python
frappe.db.sql(
    "SELECT name FROM `tabSales Order` WHERE name=%(name)s FOR UPDATE",
    {"name": sales_order_name},
)
```

Load the document and require company `Doh Myot Daw BBQ & Restaurant`, `docstatus == 0`, and state Open/Billing. Validate `DMT.custom_cashier_printer`. Load `DMT.custom_cashier_print_format`, require the Print Format exists and `doc_type == "Sales Order"`.

Render:

```python
pdf = frappe.get_print(
    "Sales Order",
    sales_order.name,
    print_format=print_format,
    as_pdf=True,
)
```

Create:

```python
job = frappe.new_doc("BCN Print Job")
job.request_id = request_id
job.document_type = "Sales Order"
job.document_name = sales_order.name
job.printer_name = printer_name
job.print_format = print_format
job.pdf_base64 = encode_pdf_base64(pdf)
job.status = "Pending"
job.attempt_count = 0
job.requested_by = current_user
job.requested_at = frappe.utils.now()
job.insert(ignore_permissions=True)
```

If Open, set `custom_restaurant_status = "Billing"` and save with `ignore_permissions=True` in the same request. If already Billing, `is_reprint=True`.

- [ ] **Step 6: Implement submitted Closed new-request reprint**

For `docstatus == 1` and `custom_restaurant_status == "Closed"`, query newest prior job for that Sales Order. Require one exists. Create a new Pending job using the new `request_id`, and copy only the previous snapshot/printer/format:

```python
job.pdf_base64 = previous_job.pdf_base64
job.printer_name = previous_job.printer_name
job.print_format = previous_job.print_format
```

Do not call `frappe.get_print` and do not print Sales Invoice in this branch.

- [ ] **Step 7: Return exact first-request response**

```python
frappe.response["message"] = {
    "sales_order": sales_order.name,
    "request_id": request_id,
    "print_job": job.name,
    "status": "Pending",
    "is_reprint": is_reprint,
    "duplicate": False,
}
```

- [ ] **Step 8: Run GREEN + full contract suite**

```powershell
python -m pytest tests/test_ourcity_server_script_contract.py -q
```

Expected: all tests PASS.

- [ ] **Step 9: Commit and review**

```powershell
git add server_scripts/mobile/cashier_print_bill.py tests/test_ourcity_server_script_contract.py
git commit -m "feat: queue request-idempotent cashier snapshots"
```

Run separate code review before Task 4.

---

### Task 4: Add Timeout-Safe Printer Claim and Result APIs

**Files:**
- Create: `server_scripts/mobile/print_jobs.py`
- Create: `server_scripts/mobile/print_job_result.py`
- Modify: `tests/test_ourcity_server_script_contract.py`

**Interfaces:**
- Consumes: `BCN Print Job`, authenticated role `BCN Printer Client`, claim `printers`, result `job_name/status/error_message`.
- Produces: stale Processing -> Failed normalization; one atomic Pending -> Processing claim; owned terminal result with retry-safe same-terminal POST.

- [ ] **Step 1: Add failing claim/result reliability tests**

```python
def test_print_jobs_times_out_stale_processing_instead_of_requeueing():
    source = _read(SERVER_SCRIPTS / "print_jobs.py")
    assert "BCN Printer Client" in source
    assert "FOR UPDATE" in source
    assert "60" in source
    assert "Print result unknown after client timeout" in source
    assert 'stale_job.status = "Failed"' in source
    assert 'stale_job.status = "Pending"' not in source
    assert 'job.status = "Processing"' in source
    assert "claimed_by" in source
    assert "claimed_at" in source
    assert "attempt_count" in source


def test_print_job_result_is_owned_and_retry_safe():
    source = _read(SERVER_SCRIPTS / "print_job_result.py")
    assert "BCN Printer Client" in source
    assert "claimed_by" in source
    assert '["Printed", "Failed"]' in source
    assert '"duplicate": True' in source
    assert "FOR UPDATE" in source
    assert "conflict" in source.lower()
```

- [ ] **Step 2: Run RED**

```powershell
python -m pytest tests/test_ourcity_server_script_contract.py -k "print_job" -q
```

Expected: FAIL because the queue API files do not exist.

- [ ] **Step 3: Implement `print_jobs.py` role/printer parsing**

Require `BCN Printer Client`. Parse `printers` from list or JSON string with `json.loads`, strip values, remove duplicates, and throw if empty.

- [ ] **Step 4: Normalize stale Processing to Failed, never Pending**

Compute cutoff:

```python
cutoff = frappe.utils.add_to_date(
    frappe.utils.now_datetime(), seconds=-60
)
```

For Processing jobs matching supplied printer names and older than cutoff, lock each row before changing it. If still Processing and still stale, set:

```python
stale_job.status = "Failed"
stale_job.error_message = "Print result unknown after client timeout"
stale_job.save(ignore_permissions=True)
```

Preserve `claimed_by`, `claimed_at`, and `attempt_count` for audit. Do not clear claim metadata and do not set Pending.

- [ ] **Step 5: Claim one oldest matching Pending job atomically**

Select oldest Pending name matching supplied printers. Lock exact row with `FOR UPDATE`, reload, require still Pending, then:

```python
job.status = "Processing"
job.claimed_by = current_user
job.claimed_at = frappe.utils.now()
job.attempt_count = int(job.attempt_count or 0) + 1
job.save(ignore_permissions=True)
```

Return exactly one job including `name`, `request_id`, document fields, printer, format, `pdf_base64`, `attempt_count`. Return `{"job": None}` when no match.

- [ ] **Step 6: Implement `print_job_result.py`**

Require role, lock exact job, accept only Printed/Failed, require `claimed_by == current_user`.

Behavior:

```text
Processing + Printed -> Printed, printed_at=now, clear error
Processing + Failed  -> Failed, exact client error
Printed + Printed    -> duplicate=true, no mutation
Failed + Failed      -> duplicate=true, no mutation
Printed + Failed     -> conflict
Failed + Printed     -> conflict
```

The last case includes a late Printed result after server timeout-to-Failed.

- [ ] **Step 7: Run GREEN + regression**

```powershell
python -m pytest tests/test_ourcity_server_script_contract.py -q
```

- [ ] **Step 8: Commit and review**

```powershell
git add server_scripts/mobile/print_jobs.py server_scripts/mobile/print_job_result.py tests/test_ourcity_server_script_contract.py
git commit -m "feat: add timeout-safe cashier print queue APIs"
```

Run separate code review before Task 5.

---

### Task 5: Add Atomic Payment Finalization and Retry Resolution

**Files:**
- Modify: `server_scripts/mobile/cashier_billing.py`
- Modify: `tests/test_ourcity_server_script_contract.py`

**Interfaces:**
- Consumes: `action=Pay`, `sales_order`, JSON tender list, DMT payment modes/accounts.
- Produces: submitted Closed SO, exactly one submitted SI with `update_stock=1`, submitted PE(s), zero outstanding, retry response with `duplicate=true`.

- [ ] **Step 1: Add failing payment contract test**

```python
def test_cashier_pay_finalizes_sales_order_invoice_and_payments_atomically():
    source = _read(SERVER_SCRIPTS / "cashier_billing.py")
    assert 'action == "Pay"' in source
    assert "FOR UPDATE" in source
    assert 'custom_restaurant_status = "Closed"' in source
    assert ".submit()" in source
    assert "update_stock = 1" in source
    assert "Payment Entry" in source
    assert "sales_order" in source
    assert '"duplicate"' in source
    assert "frappe.db.commit" not in source
    assert "frappe.db.rollback" not in source
    assert "Delivery Note" not in source
```

- [ ] **Step 2: Run RED**

```powershell
python -m pytest tests/test_ourcity_server_script_contract.py::test_cashier_pay_finalizes_sales_order_invoice_and_payments_atomically -q
```

- [ ] **Step 3: Parse and validate tenders**

`payments` may arrive as JSON string; use `json.loads`. Keep only positive amounts. Every mode must exist in `DMT.payments` and resolve to a usable company Mode of Payment account. Reject empty usable allocations.

Allocation rules:

```text
non-cash: amount must not exceed remaining due
cash: tender may exceed remaining due
cash PE allocation = min(cash tender, remaining due)
change_amount = cash tender - cash PE allocation
```

Require final remaining due = 0.

- [ ] **Step 4: Resolve retry before creating new documents**

After locking SO, when `docstatus == 1` and status Closed, query submitted Sales Invoice Item rows linked by `sales_order`. Require exactly one distinct submitted Sales Invoice. Resolve submitted Payment Entry names through Payment Entry Reference rows for that SI. Return existing identities with `duplicate=True`.

- [ ] **Step 5: Finalize a new Draft Open/Billing order atomically**

Freeze SO `net_total`, `total_taxes_and_charges`, `grand_total`. If Open, set Billing in memory. Then set `custom_restaurant_status="Closed"` and submit SO.

Create Sales Invoice from the submitted Sales Order with ERPNext's whitelisted Sales Order mapper through safe-exec `frappe.call`, set:

```python
sales_invoice.update_stock = 1
```

Preserve Sales Invoice Item -> Sales Order links. Recalculate/validate and require frozen SO totals equal SI totals within currency rounding tolerance before submit.

Create one Payment Entry per positive allocated tender using ERPNext standard Payment Entry creation/mapping, set the requested Mode of Payment/account, reference the Sales Invoice, allocated amount, reference number/date as required, then submit. Re-read SI and require outstanding amount is zero within rounding tolerance.

- [ ] **Step 6: Return exact response**

```python
frappe.response["message"] = {
    "sales_order": sales_order.name,
    "sales_invoice": sales_invoice.name,
    "payment_entries": payment_entries,
    "change_amount": float(change_amount),
    "duplicate": False,
}
```

- [ ] **Step 7: Run GREEN + full contract suite**

```powershell
python -m pytest tests/test_ourcity_server_script_contract.py -q
```

- [ ] **Step 8: Commit and review**

```powershell
git add server_scripts/mobile/cashier_billing.py tests/test_ourcity_server_script_contract.py
git commit -m "feat: finalize cashier sales order payments"
```

Run separate code review before Flutter refactor.

---

### Task 6: Refactor Flutter Cashier Domain and Repository to Sales Orders

**Files:**
- Modify: `mobile/bcn_restaurant_mobile/lib/features/cashier/domain/cashier_models.dart`
- Modify: `mobile/bcn_restaurant_mobile/lib/features/cashier/data/cashier_repository.dart`
- Create: `mobile/bcn_restaurant_mobile/test/features/cashier/cashier_models_test.dart`
- Create: `mobile/bcn_restaurant_mobile/test/features/cashier/cashier_repository_test.dart`

**Interfaces:**
- Consumes: GET `{bills,modes}`, Pay `{action,sales_order,payments}`, Pay final identities.
- Produces: `CashierBill`, `CashierBillingResponse`, `CashierPaymentResult`; repository `getBilling()` and `paySplit(...)`.

- [ ] **Step 1: Write failing model test**

```dart
test('parses a Sales Order cashier bill with print state', () {
  final response = CashierBillingResponse.fromJson({
    'bills': [
      {
        'sales_order': 'SAL-ORD-2026-00005',
        'customer': 'Table 01',
        'customer_name': 'Table 01',
        'grand_total': 10500,
        'restaurant_status': 'Billing',
        'last_print_status': 'Failed',
        'last_print_job': 'PRINT-JOB-X',
        'items': [],
        'taxes': [],
      },
    ],
    'modes': [{'name': 'Cash', 'default': true}],
  });
  expect(response.bills.single.salesOrder, 'SAL-ORD-2026-00005');
  expect(response.bills.single.restaurantStatus, 'Billing');
  expect(response.bills.single.lastPrintStatus, 'Failed');
});
```

- [ ] **Step 2: Write failing Pay payload test**

Assert `paySplit` posts:

```dart
{
  'action': 'Pay',
  'sales_order': 'SAL-ORD-2026-00005',
  'payments': jsonEncode([
    {'mode_of_payment': 'Cash', 'amount': 10500.0},
  ]),
}
```

- [ ] **Step 3: Run RED**

```powershell
cd mobile\bcn_restaurant_mobile
flutter test test/features/cashier/cashier_models_test.dart test/features/cashier/cashier_repository_test.dart
```

- [ ] **Step 4: Replace invoice-first types/repository**

Define `CashierBill` using Sales Order fields from the spec. Define `CashierPaymentResult` with `salesOrder`, `salesInvoice`, `paymentEntries`, `changeAmount`, `duplicate`. `getBilling()` calls GET `bcn_cashier_billing`; `paySplit` posts `sales_order` and tender JSON. Remove cashier compatibility methods that depend on invoice-name Record Print/Pay.

- [ ] **Step 5: Run GREEN**

```powershell
flutter test test/features/cashier/cashier_models_test.dart test/features/cashier/cashier_repository_test.dart
```

- [ ] **Step 6: Commit and review**

```powershell
git add mobile/bcn_restaurant_mobile/lib/features/cashier mobile/bcn_restaurant_mobile/test/features/cashier
git commit -m "refactor: make cashier billing sales order based"
```

---

### Task 7: Replace Mobile Print Gateway with Request-Idempotent Server-Script Queue Request

**Files:**
- Create: `mobile/bcn_restaurant_mobile/lib/features/printing/domain/cashier_bill_print_result.dart`
- Modify: `mobile/bcn_restaurant_mobile/lib/features/printing/data/windows_print_repository.dart`
- Modify: `mobile/bcn_restaurant_mobile/test/features/printing/windows_print_repository_test.dart`

**Interfaces:**
- Consumes: POST `bcn_cashier_print_bill` with `sales_order`, `request_id`.
- Produces: `CashierBillPrintResult(salesOrder, requestId, printJob, status, isReprint, duplicate)`.

- [ ] **Step 1: Write failing exact-contract test**

```dart
test('queues cashier bill with request id through OurCity alias', () async {
  final api = _RecordingApiClient(postResponse: {
    'sales_order': 'SAL-ORD-2026-00005',
    'request_id': 'REQ-A',
    'print_job': 'PRINT-JOB-X',
    'status': 'Pending',
    'is_reprint': false,
    'duplicate': false,
  });
  final result = await WindowsPrintRepository(api).requestCashierBill(
    salesOrder: 'SAL-ORD-2026-00005',
    requestId: 'REQ-A',
  );
  expect(api.postCalls.single.method, 'bcn_cashier_print_bill');
  expect(api.postCalls.single.data, {
    'sales_order': 'SAL-ORD-2026-00005',
    'request_id': 'REQ-A',
  });
  expect(result.requestId, 'REQ-A');
  expect(result.printJob, 'PRINT-JOB-X');
});
```

Delete cashier tests for custom-app `get_print_status`/`retry_print_job` dotted methods.

- [ ] **Step 2: Run RED**

```powershell
flutter test test/features/printing/windows_print_repository_test.dart
```

- [ ] **Step 3: Implement result model and gateway**

Expose:

```dart
abstract interface class WindowsPrintGateway {
  Future<CashierBillPrintResult> requestCashierBill({
    required String salesOrder,
    required String requestId,
  });
}
```

Repository posts only to `bcn_cashier_print_bill` with both fields.

- [ ] **Step 4: Add retry-id reuse test**

At repository level, two calls supplied the same `requestId` must send the same id unchanged. Repository must never silently generate a replacement id after transport failure.

- [ ] **Step 5: Run GREEN**

```powershell
flutter test test/features/printing/windows_print_repository_test.dart
```

- [ ] **Step 6: Commit and review**

```powershell
git add mobile/bcn_restaurant_mobile/lib/features/printing mobile/bcn_restaurant_mobile/test/features/printing/windows_print_repository_test.dart
git commit -m "refactor: queue idempotent cashier prints through OurCity"
```

---

### Task 8: Refactor Cashier UI for Open/Billing, Request IDs, Payment, and Manual Reprint

**Files:**
- Modify: `mobile/bcn_restaurant_mobile/lib/features/cashier/presentation/cashier_screen.dart`
- Create: `mobile/bcn_restaurant_mobile/test/features/cashier/cashier_screen_test.dart`

**Interfaces:**
- Consumes: Draft SO bills, print gateway with request id, payment repository.
- Produces: Open `Print Bill + Payment`; Billing `Reprint Bill + Payment`; Failed never auto-reprints; success refresh + immediate manual post-payment Reprint.

- [ ] **Step 1: Add action/status widget tests**

Create fixtures for Open and Billing bills. Assert Open contains `Print Bill` and `Payment`; Billing contains `Reprint Bill`, `Payment`, and `Last Print: Failed` for Failed state.

- [ ] **Step 2: Add request-id behavior tests**

Use a fake print gateway that records request ids. Assert one intentional button tap generates one non-empty request id. Simulate a transport retry of the same operation and assert the same id is reused. Tap intentional Reprint again and assert a different id is generated.

Use the app's existing UUID/random-id utility if present; otherwise add a small injectable request-id factory in the cashier screen/controller layer so tests can supply deterministic ids such as `REQ-A`, `REQ-B`.

- [ ] **Step 3: Add Failed-no-auto-reprint test**

Render a Billing bill with `lastPrintStatus='Failed'`; pump without tapping anything and assert print gateway call count remains zero.

- [ ] **Step 4: Add payment-success behavior test**

Fake Pay returns:

```dart
CashierPaymentResult(
  salesOrder: 'SAL-ORD-2026-00005',
  salesInvoice: 'ACC-SINV-2026-00001',
  paymentEntries: const ['ACC-PAY-2026-00001'],
  changeAmount: 0,
  duplicate: false,
)
```

Assert active bill is refreshed/removed, table providers are invalidated, and success UI offers manual `Reprint Bill` using finalized SO identity. That manual action generates a new request id.

- [ ] **Step 5: Run RED**

```powershell
flutter test test/features/cashier/cashier_screen_test.dart
```

- [ ] **Step 6: Refactor screen minimally**

Search/identity uses `salesOrder`. Open button label `Print Bill`; Billing button `Reprint Bill`. Status row shows last print state. Payment uses Draft SO amount. Generate request id at intentional action boundary and retain it for retries of the same in-flight operation. Never auto-call Reprint on Failed/timeout.

- [ ] **Step 7: Run GREEN + Flutter regression**

```powershell
flutter test
```

- [ ] **Step 8: Commit and review**

```powershell
git add mobile/bcn_restaurant_mobile/lib/features/cashier/presentation/cashier_screen.dart mobile/bcn_restaurant_mobile/test/features/cashier/cashier_screen_test.dart
git commit -m "feat: show request-safe draft sales order cashier flow"
```

---

### Task 9: Document OurCity Queue Schema/Deployment and Verify Contracts

**Files:**
- Modify: `docs/server-script-mobile.md`
- Modify: `tests/test_ourcity_server_script_contract.py`

**Interfaces:**
- Consumes: all implemented aliases/config/roles/DocType.
- Produces: exact manual OurCity setup checklist and final source-control regression contract.

- [ ] **Step 1: Add failing docs contract test**

Require docs contain:

```text
bcn_cashier_billing
bcn_cashier_print_bill
bcn_print_jobs
bcn_print_job_result
BCN Print Job
request_id
Unique
BCN Printer Client
custom_cashier_printer
custom_cashier_print_format
Print result unknown after client timeout
never automatically requeue
API Key
API Secret
```

- [ ] **Step 2: Run RED**

```powershell
python -m pytest tests/test_ourcity_server_script_contract.py -q
```

- [ ] **Step 3: Document exact Custom DocType fields**

Document:

```text
request_id       Data, Unique
document_type    Link -> DocType
document_name    Dynamic Link -> document_type
printer_name     Data
print_format     Link -> Print Format
pdf_base64       Long Text
status           Select Pending/Processing/Printed/Failed
attempt_count    Int
error_message    Long Text
requested_by     Link -> User
requested_at     Datetime
claimed_by       Link -> User
claimed_at       Datetime
printed_at       Datetime
```

Also document Role/API user, DMT custom fields, four aliases, 60-second timeout-to-Failed rule, manual Reprint/new request id rule, and that Git push does not deploy Server Script records to OurCity.

- [ ] **Step 4: Run repository verification**

```powershell
python -m pytest tests/test_ourcity_server_script_contract.py -q
cd mobile\bcn_restaurant_mobile
flutter test
flutter analyze
```

Expected: all tests pass; analyzer has no new errors.

- [ ] **Step 5: Commit and review**

```powershell
git add docs/server-script-mobile.md tests/test_ourcity_server_script_contract.py
git commit -m "docs: document request-safe cashier print queue deployment"
```

---

## Integration Handoff to Windows Plan

After Tasks 3-9 pass their individual review gates, execute `docs/superpowers/plans/2026-09-07-cashier-polling-windows-client.md` against `HtayOoLwin/local_printers_winapp`. The Windows plan must follow the same invariant: timed-out Processing jobs are not redelivered automatically. Do not declare end-to-end printing complete until the Windows plan and final live smoke tests pass.
