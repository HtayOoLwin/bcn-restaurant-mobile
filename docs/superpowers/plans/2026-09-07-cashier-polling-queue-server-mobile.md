# Cashier Polling Queue Server + Mobile Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the OurCity Server-Script-only cashier flow backed by Draft Sales Orders and a durable `BCN Print Job` polling queue, including Flutter cashier UI/payment integration.

**Architecture:** Cashier billing remains Sales-Order-first. `bcn_cashier_print_bill` stores an immutable Draft Sales Order PDF snapshot in a new Pending `BCN Print Job`; Windows clients claim jobs through `bcn_print_jobs` and report results through `bcn_print_job_result`. Payment remains independent from print success and atomically submits the Sales Order, creates one Sales Invoice with `update_stock = 1`, creates Payment Entry records, and closes the restaurant order.

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
- Stale Processing jobs become claimable after 60 seconds.
- Reprint creates a new job; old jobs remain immutable audit history.
- Do not call `frappe.db.commit()` or `frappe.db.rollback()` inside Server Scripts.

---

## File Structure

- `server_scripts/mobile/create_order.py` — apply/recalculate DMT tax state on Draft Sales Orders.
- `server_scripts/mobile/cashier_billing.py` — GET Open/Billing Sales Order bills and POST payment finalization.
- `server_scripts/mobile/cashier_print_bill.py` — render/encode Sales Order snapshot, create Pending queue job, freeze Open -> Billing, copy snapshot for Closed immediate reprint.
- `server_scripts/mobile/print_jobs.py` — printer-client claim endpoint with stale recovery and row lock.
- `server_scripts/mobile/print_job_result.py` — ownership-enforced Printed/Failed result endpoint with idempotent same-terminal retry.
- `tests/test_ourcity_server_script_contract.py` — source-control contract tests for all aliases/invariants.
- `docs/server-script-mobile.md` — OurCity alias/config/deployment documentation.
- `mobile/bcn_restaurant_mobile/lib/features/cashier/domain/cashier_models.dart` — Sales-Order bill, print status, payment result models.
- `mobile/bcn_restaurant_mobile/lib/features/cashier/data/cashier_repository.dart` — GET bills and Pay by `sales_order`.
- `mobile/bcn_restaurant_mobile/lib/features/printing/domain/cashier_bill_print_result.dart` — Pending queue result model.
- `mobile/bcn_restaurant_mobile/lib/features/printing/data/windows_print_repository.dart` — mobile call to `bcn_cashier_print_bill` only; no custom-app status/retry endpoints for cashier v1.
- `mobile/bcn_restaurant_mobile/lib/features/cashier/presentation/cashier_screen.dart` — Open/Billing card actions, last print status, payment and immediate post-payment reprint.
- Flutter tests under `mobile/bcn_restaurant_mobile/test/features/cashier/` and `.../printing/`.

---

## Preflight Gate 0: Prove Raw PDF Bytes -> Base64 in OurCity Safe Exec

This gate must pass before Tasks 1-7. It is a live-site feasibility check, not production code. Create/replace temporary API Server Script `bcn_cashier_capability_probe` with the following exact code:

```python
sales_order = (frappe.form_dict.get("sales_order") or "").strip()
if not sales_order:
    frappe.throw("sales_order is required")

pdf = frappe.get_print(
    "Sales Order",
    sales_order,
    print_format="Standard",
    as_pdf=True,
)

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

pdf_base64 = "".join(out)
frappe.response["message"] = {
    "pdf_length": length,
    "base64_length": len(pdf_base64),
    "base64_prefix": pdf_base64[:8],
    "pdf_base64": pdf_base64,
}
```

- [ ] **Step 1: Run the probe with Draft Sales Order `SAL-ORD-2026-00005`**

```powershell
$so = "SAL-ORD-2026-00005"
$result = Invoke-RestMethod `
  -Uri "https://ourcity.s.frappe.cloud/api/method/bcn_cashier_capability_probe" `
  -Method Post `
  -WebSession $FrappeSession `
  -Body @{ sales_order = $so } `
  -ContentType "application/x-www-form-urlencoded"
$result.message | Select-Object pdf_length, base64_length, base64_prefix
```

Expected: `pdf_length > 100`, `base64_length > pdf_length`, `base64_prefix = JVBERi0`.

- [ ] **Step 2: Verify the returned payload decodes as PDF on Windows**

```powershell
$bytes = [Convert]::FromBase64String($result.message.pdf_base64)
$bytes.Length
[System.Text.Encoding]::ASCII.GetString($bytes[0..4])
```

Expected: decoded byte length equals `pdf_length`; header starts `%PDF-`.

- [ ] **Step 3: Gate execution**

If either check fails, stop before Task 1 and return to design. Do not silently change transport/payload. If both pass, disable/delete the temporary probe and continue.

---

### Task 1: Keep Draft Sales Order Tax/Service-Charge Totals Stable

**Files:**
- Modify: `server_scripts/mobile/create_order.py`
- Modify: `tests/test_ourcity_server_script_contract.py`

**Interfaces:**
- Consumes: `POS Profile DMT.taxes_and_charges`, current item append/reuse logic.
- Produces: every mutated Open Draft Sales Order has DMT tax rows and recalculated totals before save.

- [ ] **Step 1: Add failing contract test**

```python
def test_create_order_applies_and_recalculates_dmt_taxes():
    source = _read(SERVER_SCRIPTS / "create_order.py")
    assert "profile.taxes_and_charges" in source
    assert "sales_order.taxes_and_charges" in source
    assert "sales_order.set_taxes()" in source
    assert "sales_order.calculate_taxes_and_totals()" in source
```

- [ ] **Step 2: Run RED**

```powershell
python -m pytest tests/test_ourcity_server_script_contract.py::test_create_order_applies_and_recalculates_dmt_taxes -q
```

Expected: FAIL on current source.

- [ ] **Step 3: Apply DMT tax template only when needed**

After `profile = frappe.get_doc("POS Profile", POS_PROFILE)` and new Sales Order header initialization, add:

```python
if is_new_order and profile.taxes_and_charges:
    sales_order.taxes_and_charges = profile.taxes_and_charges
    sales_order.set_taxes()
```

Immediately before `custom_client_order_id` assignment/save, add:

```python
if profile.taxes_and_charges and not sales_order.taxes_and_charges:
    sales_order.taxes_and_charges = profile.taxes_and_charges
    sales_order.set_taxes()

sales_order.calculate_taxes_and_totals()
```

Do not replace existing tax child rows on every waiter round.

- [ ] **Step 4: Run GREEN + regression**

```powershell
python -m pytest tests/test_ourcity_server_script_contract.py -q
```

Expected: all tests PASS.

- [ ] **Step 5: Commit**

```powershell
git add server_scripts/mobile/create_order.py tests/test_ourcity_server_script_contract.py
git commit -m "feat: keep restaurant draft totals aligned with DMT taxes"
```

---

### Task 2: Add Cashier Bill List Models and GET API

**Files:**
- Create: `server_scripts/mobile/cashier_billing.py`
- Modify: `tests/test_ourcity_server_script_contract.py`

**Interfaces:**
- Consumes: Draft Sales Orders `docstatus=0`, states Open/Billing, POS Profile payment rows, `BCN Print Job` history when DocType exists.
- Produces: `bcn_cashier_billing` GET `{bills, modes}` with `sales_order`, `restaurant_status`, `last_print_status`, `last_print_job`.

- [ ] **Step 1: Add failing source contract test**

```python
def test_cashier_billing_lists_open_and_billing_sales_order_bills():
    path = SERVER_SCRIPTS / "cashier_billing.py"
    assert path.exists()
    source = _read(path)
    assert 'POS_PROFILE = "DMT"' in source
    assert '"docstatus": 0' in source
    assert '["Open", "Billing"]' in source
    assert '"bills"' in source
    assert '"modes"' in source
    assert '"last_print_status"' in source
    assert '"last_print_job"' in source
    assert "Restaurant Table Session" not in source
```

- [ ] **Step 2: Run RED**

```powershell
python -m pytest tests/test_ourcity_server_script_contract.py::test_cashier_billing_lists_open_and_billing_sales_order_bills -q
```

Expected: FAIL because file does not exist.

- [ ] **Step 3: Implement GET branch**

Start with exact constants and cashier role check. Use `action = (frappe.form_dict.get("action") or "").strip()` and, when action is blank, query:

```python
orders = frappe.get_all(
    "Sales Order",
    filters={
        "company": COMPANY,
        "docstatus": 0,
        "custom_restaurant_status": ["in", ["Open", "Billing"]],
    },
    fields=[
        "name", "customer", "creation", "net_total",
        "total_taxes_and_charges", "grand_total", "currency",
        "custom_restaurant_status",
    ],
    order_by="creation asc",
    limit_page_length=500,
)
```

For each order, load item/tax rows and newest `BCN Print Job` where `document_type="Sales Order"` and `document_name=order.name`; if the DocType is not yet configured during source-only development, guard the history query with `frappe.db.exists("DocType", "BCN Print Job")`.

Return:

```python
frappe.response["message"] = {"bills": bills, "modes": modes}
```

Payment mode rows come from `frappe.get_doc("POS Profile", POS_PROFILE).payments`; emit `{"name": mode_of_payment, "default": bool(default)}`.

- [ ] **Step 4: Run GREEN**

```powershell
python -m pytest tests/test_ourcity_server_script_contract.py -q
```

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add server_scripts/mobile/cashier_billing.py tests/test_ourcity_server_script_contract.py
git commit -m "feat: list draft sales order bills for cashier"
```

---

### Task 3: Add Draft/Closed Cashier Print Queue Endpoint

**Files:**
- Create: `server_scripts/mobile/cashier_print_bill.py`
- Modify: `tests/test_ourcity_server_script_contract.py`

**Interfaces:**
- Consumes: `sales_order`, DMT printer/print-format fields, `BCN Print Job` DocType, proven pure-Python base64 encoder.
- Produces: new Pending print job; Open -> Billing atomically; Billing creates reprint; submitted Closed copies latest snapshot.

- [ ] **Step 1: Add failing contract test**

```python
def test_cashier_print_bill_queues_snapshot_and_freezes_open_order():
    path = SERVER_SCRIPTS / "cashier_print_bill.py"
    assert path.exists()
    source = _read(path)
    assert 'POS_PROFILE = "DMT"' in source
    assert "custom_cashier_printer" in source
    assert "custom_cashier_print_format" in source
    assert 'frappe.get_print("Sales Order"' in source
    assert 'frappe.new_doc("BCN Print Job")' in source
    assert 'job.status = "Pending"' in source
    assert 'sales_order.custom_restaurant_status = "Billing"' in source
    assert "pdf_base64" in source
    assert "publish_realtime" not in source
    assert "Sales Invoice" not in source
```

Add a second test:

```python
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

Expected: FAIL because file does not exist.

- [ ] **Step 3: Implement reusable in-script pure-Python base64 encoder**

Use the exact algorithm proven in Gate 0. Keep it as a local function in this mirror; Server Script files are standalone and cannot import one another.

- [ ] **Step 4: Implement Draft Open/Billing path**

Lock Sales Order by name using `SELECT name FROM \`tabSales Order\` WHERE name=%(name)s FOR UPDATE`, then load the doc. Validate DMT printer and print format DocType is `Sales Order`. Render:

```python
pdf = frappe.get_print(
    "Sales Order",
    sales_order.name,
    print_format=print_format,
    as_pdf=True,
)
```

Create job:

```python
job = frappe.new_doc("BCN Print Job")
job.document_type = "Sales Order"
job.document_name = sales_order.name
job.printer_name = printer_name
job.print_format = print_format
job.pdf_base64 = encode_base64(pdf)
job.status = "Pending"
job.attempt_count = 0
job.requested_by = current_user
job.requested_at = frappe.utils.now()
job.insert(ignore_permissions=True)
```

If Open, set Billing and save in the same request. If Billing, leave state unchanged and mark response `is_reprint=true`.

- [ ] **Step 5: Implement submitted Closed reprint path**

For submitted Closed Sales Order, query newest prior `BCN Print Job`, load it, and create a new Pending job copying `previous_job.pdf_base64`, `printer_name`, and `print_format`. Do not call `frappe.get_print` in this branch and do not render Sales Invoice.

- [ ] **Step 6: Return exact response**

```python
frappe.response["message"] = {
    "sales_order": sales_order.name,
    "print_job": job.name,
    "status": "Pending",
    "is_reprint": is_reprint,
}
```

- [ ] **Step 7: Run GREEN**

```powershell
python -m pytest tests/test_ourcity_server_script_contract.py -q
```

Expected: PASS.

- [ ] **Step 8: Commit**

```powershell
git add server_scripts/mobile/cashier_print_bill.py tests/test_ourcity_server_script_contract.py
git commit -m "feat: queue cashier sales order snapshots"
```

---

### Task 4: Add Printer Claim and Result Server Script APIs

**Files:**
- Create: `server_scripts/mobile/print_jobs.py`
- Create: `server_scripts/mobile/print_job_result.py`
- Modify: `tests/test_ourcity_server_script_contract.py`

**Interfaces:**
- Consumes: `BCN Print Job`, authenticated user role `BCN Printer Client`, claim request `printers`, result request `job_name/status/error_message`.
- Produces: one-job claim with stale recovery; ownership-enforced terminal result with retry-safe `duplicate`.

- [ ] **Step 1: Add failing claim/result contract tests**

```python
def test_print_jobs_claim_contract():
    source = _read(SERVER_SCRIPTS / "print_jobs.py")
    assert "BCN Printer Client" in source
    assert "FOR UPDATE" in source
    assert '"Pending"' in source
    assert '"Processing"' in source
    assert "claimed_by" in source
    assert "claimed_at" in source
    assert "attempt_count" in source
    assert "60" in source
    assert '"job": None' in source or '"job": null' not in source


def test_print_job_result_is_owned_and_retry_safe():
    source = _read(SERVER_SCRIPTS / "print_job_result.py")
    assert "BCN Printer Client" in source
    assert "claimed_by" in source
    assert '["Printed", "Failed"]' in source
    assert '"duplicate": True' in source
    assert "FOR UPDATE" in source
```

- [ ] **Step 2: Run RED**

```powershell
python -m pytest tests/test_ourcity_server_script_contract.py -k "print_job" -q
```

Expected: FAIL because files do not exist.

- [ ] **Step 3: Implement `print_jobs.py`**

Parse `printers` with `json.loads` when passed as form string; normalize unique non-empty strings. Require printer-client role. Recover stale rows older than `frappe.utils.add_to_date(frappe.utils.now_datetime(), seconds=-60)` by setting Pending and clearing claim fields. Select oldest matching Pending name, lock by exact name with `FOR UPDATE`, re-read status, then set Processing, `claimed_by=current_user`, `claimed_at=frappe.utils.now()`, increment `attempt_count`, save, and return one job. Return `{"job": None}` when no match.

- [ ] **Step 4: Implement `print_job_result.py`**

Lock job row. Require requested status in `Printed/Failed`, require `claimed_by == current_user`. If Processing, apply terminal status. If already same terminal status, return `duplicate=True` without mutation. If opposite terminal state, throw conflict. Printed sets `printed_at` and clears error; Failed stores exact `error_message`.

- [ ] **Step 5: Run GREEN**

```powershell
python -m pytest tests/test_ourcity_server_script_contract.py -q
```

Expected: PASS.

- [ ] **Step 6: Commit**

```powershell
git add server_scripts/mobile/print_jobs.py server_scripts/mobile/print_job_result.py tests/test_ourcity_server_script_contract.py
git commit -m "feat: add durable cashier print queue APIs"
```

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
    assert "Delivery Note" not in source
```

- [ ] **Step 2: Run RED**

```powershell
python -m pytest tests/test_ourcity_server_script_contract.py::test_cashier_pay_finalizes_sales_order_invoice_and_payments_atomically -q
```

Expected: FAIL because Pay branch is not implemented.

- [ ] **Step 3: Parse and validate tender list**

Accept only `payments` list entries with positive amount and configured DMT Mode of Payment. Resolve each mode's company account. Allocate non-cash first in request order up to remaining amount; reject non-cash tender above remaining amount. Allocate Cash only up to remaining amount and compute excess as `change_amount`. Require total usable allocation to cover the bill.

- [ ] **Step 4: Implement retry resolution before new finalization**

After locking the Sales Order, if submitted + Closed, find distinct submitted Sales Invoice names through Sales Invoice Item `sales_order = sales_order.name`. Exactly one -> reuse; zero -> inconsistent finalization error; more than one -> conflict. Resolve submitted Payment Entries through Payment Entry Reference rows for that SI and return existing identities with `duplicate=true`.

- [ ] **Step 5: Implement new finalization transaction**

For Draft Open/Billing: freeze `net_total`, `total_taxes_and_charges`, `grand_total`; set Open -> Billing if needed; then set in-memory `custom_restaurant_status="Closed"` and submit SO. Create SI from Sales Order using ERPNext mapped/document creation pattern already supported by safe exec, set `update_stock=1`, preserve source links, validate frozen totals, submit SI. Create one PE per positive allocation, referencing SI. Re-read SI outstanding and require zero.

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

- [ ] **Step 7: Run GREEN + full server contract suite**

```powershell
python -m pytest tests/test_ourcity_server_script_contract.py -q
```

Expected: PASS.

- [ ] **Step 8: Commit**

```powershell
git add server_scripts/mobile/cashier_billing.py tests/test_ourcity_server_script_contract.py
git commit -m "feat: finalize cashier sales order payments"
```

---

### Task 6: Refactor Flutter Cashier Domain and Repository to Sales Orders

**Files:**
- Modify: `mobile/bcn_restaurant_mobile/lib/features/cashier/domain/cashier_models.dart`
- Modify: `mobile/bcn_restaurant_mobile/lib/features/cashier/data/cashier_repository.dart`
- Create: `mobile/bcn_restaurant_mobile/test/features/cashier/cashier_models_test.dart`
- Create: `mobile/bcn_restaurant_mobile/test/features/cashier/cashier_repository_test.dart`

**Interfaces:**
- Consumes: GET `{bills,modes}`, Pay request `{action,sales_order,payments}`, Pay response final identities.
- Produces: `CashierBill`, `CashierBillingResponse.bills`, `CashierPaymentResult`; repository methods `getBilling()` and `paySplit(salesOrder, payments)`.

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

- [ ] **Step 2: Write failing repository payload test**

Assert `paySplit` POSTs method `bcn_cashier_billing` with:

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

Expected: FAIL because invoice-first types/API fields remain.

- [ ] **Step 4: Replace invoice-first types**

Define `CashierBill` with fields from the spec (`salesOrder`, customer data, totals, currency, `restaurantStatus`, `lastPrintStatus`, `lastPrintJob`, items, taxes). `CashierBillingResponse` exposes `List<CashierBill> bills` and payment modes. Define `CashierPaymentResult` with `salesOrder`, `salesInvoice`, `paymentEntries`, `changeAmount`, `duplicate`.

- [ ] **Step 5: Update repository methods**

`getBilling()` stays GET `bcn_cashier_billing`. `paySplit` accepts `required String salesOrder` and returns `CashierPaymentResult`. Remove compatibility invoice-name Pay/Record Print methods from the cashier repository.

- [ ] **Step 6: Run GREEN**

```powershell
flutter test test/features/cashier/cashier_models_test.dart test/features/cashier/cashier_repository_test.dart
```

Expected: PASS.

- [ ] **Step 7: Commit**

```powershell
git add lib/features/cashier test/features/cashier
git commit -m "refactor: make cashier billing sales order based"
```

---

### Task 7: Replace Mobile Print Gateway with Server-Script Queue Request

**Files:**
- Create: `mobile/bcn_restaurant_mobile/lib/features/printing/domain/cashier_bill_print_result.dart`
- Modify: `mobile/bcn_restaurant_mobile/lib/features/printing/data/windows_print_repository.dart`
- Modify: `mobile/bcn_restaurant_mobile/test/features/printing/windows_print_repository_test.dart`

**Interfaces:**
- Consumes: POST `bcn_cashier_print_bill` with `sales_order`.
- Produces: `CashierBillPrintResult(salesOrder, printJob, status, isReprint)`.

- [ ] **Step 1: Rewrite failing exact-contract test**

```dart
test('queues cashier bill through OurCity Server Script alias', () async {
  final api = _RecordingApiClient(postResponse: {
    'sales_order': 'SAL-ORD-2026-00005',
    'print_job': 'PRINT-JOB-X',
    'status': 'Pending',
    'is_reprint': false,
  });
  final result = await WindowsPrintRepository(api)
      .requestCashierBill('SAL-ORD-2026-00005');
  expect(api.postCalls.single.method, 'bcn_cashier_print_bill');
  expect(api.postCalls.single.data, {'sales_order': 'SAL-ORD-2026-00005'});
  expect(result.printJob, 'PRINT-JOB-X');
  expect(result.status, 'Pending');
});
```

Delete tests for custom-app `get_print_status` and `retry_print_job` from this cashier repository contract.

- [ ] **Step 2: Run RED**

```powershell
flutter test test/features/printing/windows_print_repository_test.dart
```

Expected: FAIL because current repository calls dotted custom-app methods with `invoice_name`.

- [ ] **Step 3: Implement queue result model and repository**

Expose:

```dart
abstract interface class WindowsPrintGateway {
  Future<CashierBillPrintResult> requestCashierBill(String salesOrder);
}
```

Use method `bcn_cashier_print_bill` and payload `{'sales_order': salesOrder}` only.

- [ ] **Step 4: Run GREEN**

```powershell
flutter test test/features/printing/windows_print_repository_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add lib/features/printing test/features/printing/windows_print_repository_test.dart
git commit -m "refactor: queue cashier prints through OurCity"
```

---

### Task 8: Refactor Cashier UI for Open/Billing, Queue Status, Payment, and Immediate Reprint

**Files:**
- Modify: `mobile/bcn_restaurant_mobile/lib/features/cashier/presentation/cashier_screen.dart`
- Create: `mobile/bcn_restaurant_mobile/test/features/cashier/cashier_screen_test.dart`

**Interfaces:**
- Consumes: `CashierBillingResponse.bills`, `CashierBill.restaurantStatus/lastPrintStatus`, print gateway, payment repository.
- Produces: Open `Print Bill + Payment`; Billing `Reprint Bill + Payment`; success refresh and immediate post-payment reprint action.

- [ ] **Step 1: Add widget tests for action labels**

Create fixtures for one Open bill and one Billing bill. Assert Open card contains `Print Bill` and `Payment`; Billing card contains `Reprint Bill`, `Payment`, and `Last Print: Failed` when supplied.

- [ ] **Step 2: Add payment-success behavior test**

Use fake repositories so Pay returns:

```dart
CashierPaymentResult(
  salesOrder: 'SAL-ORD-2026-00005',
  salesInvoice: 'ACC-SINV-2026-00001',
  paymentEntries: const ['ACC-PAY-2026-00001'],
  changeAmount: 0,
  duplicate: false,
)
```

Assert success UI offers `Reprint Bill` using the finalized Sales Order identity and that cashier/table providers are invalidated.

- [ ] **Step 3: Run RED**

```powershell
flutter test test/features/cashier/cashier_screen_test.dart
```

Expected: FAIL on current invoice-centric UI.

- [ ] **Step 4: Refactor screen**

Rename invoice collections/state to bills/Sales Orders. Search uses customer/table + `salesOrder`. Print handler calls gateway with `bill.salesOrder`, then invalidates cashier billing so Pending status is shown. Payment uses `bill.grandTotal` as due amount and posts Sales Order tenders. Remove custom-app known-print-job status routing from cashier v1.

- [ ] **Step 5: Add immediate post-payment reprint action**

After successful Pay, show a success dialog/snackbar/action that retains finalized `salesOrder`; `Reprint Bill` calls `bcn_cashier_print_bill` so server copies the original snapshot. Once dismissed, no historical paid-bills browser is added.

- [ ] **Step 6: Run GREEN + Flutter regression suite**

```powershell
flutter test
```

Expected: all tests PASS.

- [ ] **Step 7: Commit**

```powershell
git add lib/features/cashier/presentation/cashier_screen.dart test/features/cashier/cashier_screen_test.dart
git commit -m "feat: show draft sales order cashier flow"
```

---

### Task 9: Document OurCity Setup and Verify Server/Mobile Contract

**Files:**
- Modify: `docs/server-script-mobile.md`
- Modify: `tests/test_ourcity_server_script_contract.py`

**Interfaces:**
- Consumes: all implemented aliases/config fields/roles/DocType.
- Produces: exact manual deployment checklist and regression contract.

- [ ] **Step 1: Extend docs contract test**

Assert docs mention aliases:

```text
bcn_cashier_billing
bcn_cashier_print_bill
bcn_print_jobs
bcn_print_job_result
```

and config terms `BCN Print Job`, `BCN Printer Client`, `custom_cashier_printer`, `custom_cashier_print_format`, `API Key`, `API Secret`, `60 seconds`.

- [ ] **Step 2: Run RED**

```powershell
python -m pytest tests/test_ourcity_server_script_contract.py -q
```

Expected: FAIL until docs are updated.

- [ ] **Step 3: Update deployment instructions**

Document exact Custom DocType fields from the spec, Role/user setup, POS Profile fields, Server Script aliases and source mirror mapping, and note that Git push does not deploy Server Scripts to OurCity.

- [ ] **Step 4: Run full repository verification**

```powershell
python -m pytest tests/test_ourcity_server_script_contract.py -q
cd mobile\bcn_restaurant_mobile
flutter test
flutter analyze
```

Expected: all tests PASS; analyzer has no new errors.

- [ ] **Step 5: Commit**

```powershell
git add docs/server-script-mobile.md tests/test_ourcity_server_script_contract.py
git commit -m "docs: document cashier polling queue deployment"
```

---

## Integration Handoff to Windows Plan

After Tasks 1-9 pass review, execute `docs/superpowers/plans/2026-09-07-cashier-polling-windows-client.md` against `HtayOoLwin/local_printers_winapp`. Do not declare end-to-end printing complete until that plan and the final live smoke test both pass.
