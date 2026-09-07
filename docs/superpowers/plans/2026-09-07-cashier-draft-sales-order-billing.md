# Cashier Draft Sales Order Billing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the approved cashier flow where Open/Billing Draft Sales Orders are printed and paid from the mobile app, payment finalization submits the Sales Order, creates one Sales Invoice with Update Stock enabled, creates Payment Entry records, closes the restaurant order, and returns the table to Available.

**Architecture:** OurCity remains Server-Script-only for mobile API aliases. `bcn_cashier_billing` becomes the read/pay boundary for Draft Sales Order bills, `bcn_cashier_print_bill` renders a Draft Sales Order PDF and sends the existing Windows `document_print_event`, and Flutter changes from invoice-first cashier models to Sales-Order-first bill models. Payment finalization is one database transaction and uses standard Sales Invoice Item -> Sales Order linkage for retry resolution.

**Tech Stack:** ERPNext/Frappe v16 Server Script safe execution, Python contract tests with `pytest`, Flutter/Dart + Riverpod + Dio, Windows Socket.IO local printer app.

**Spec:** `docs/superpowers/specs/2026-09-07-cashier-draft-sales-order-billing-design.md`

## Global Constraints

- Target site is exactly `https://ourcity.s.frappe.cloud`.
- Target branch is exactly `bcn-restaurant-mobile-without-kitchen-monitor`; do not merge into `main` as part of this work.
- Company is exactly `Doh Myot Daw BBQ & Restaurant`.
- POS Profile is exactly `DMT`.
- Selling Price List is exactly `Standard Selling`.
- Currency is exactly `MMK`.
- Keep one active Draft Sales Order per table/customer visit.
- Restaurant states are `Open`, `Billing`, and `Closed` in `Sales Order.custom_restaurant_status`.
- Waiter order APIs never submit the Sales Order.
- Billing freezes waiter changes.
- Cashier print source is the Draft Sales Order, not Sales Invoice.
- Payment creates one Sales Invoice with `update_stock = 1`; do not create a Delivery Note.
- Cash, Kpay, and split payment are supported.
- Successful finalization marks the Sales Order `Closed`; only then does the table become Available.
- Do not reintroduce Restaurant Table Session, Kitchen Monitor UI, Android direct printing, or Bluetooth printing.
- Do not require the `bcn_restaurant` custom app on OurCity.
- Do not call `frappe.db.commit()` or `frappe.db.rollback()` inside the payment Server Script; request-level transaction handling must provide atomicity.
- Printer configuration comes from POS Profile `DMT` custom fields `custom_cashier_printer` and `custom_cashier_print_format`.
- Payment modes come from POS Profile `DMT`; each usable mode must resolve to a company account.

---

## File Structure

### Server Script mirrors

- `server_scripts/mobile/create_order.py` — keep Draft Sales Order tax/service-charge state aligned with DMT while waiter rounds change quantities.
- `server_scripts/mobile/cashier_billing.py` — GET active Open/Billing bills and POST `action=Pay` finalization.
- `server_scripts/mobile/cashier_print_bill.py` — freeze Open -> Billing, render Draft Sales Order PDF, publish the Windows print event.

### Flutter

- `mobile/bcn_restaurant_mobile/lib/features/cashier/domain/cashier_models.dart` — Sales-Order-based cashier bill/payment models.
- `mobile/bcn_restaurant_mobile/lib/features/cashier/data/cashier_repository.dart` — GET bills and POST payment using `sales_order`.
- `mobile/bcn_restaurant_mobile/lib/features/cashier/presentation/cashier_screen.dart` — Open/Billing card state, Print/Reprint, Cash/Kpay/Split payment, refresh behavior.
- `mobile/bcn_restaurant_mobile/lib/features/printing/data/windows_print_repository.dart` — call `bcn_cashier_print_bill` with `sales_order`.
- `mobile/bcn_restaurant_mobile/lib/features/printing/domain/cashier_bill_print_result.dart` — accepted/reprint result for the Server Script print endpoint.

### Tests

- `tests/test_ourcity_server_script_contract.py` — static Server Script contract regression tests.
- `mobile/bcn_restaurant_mobile/test/features/cashier/cashier_models_test.dart` — Sales Order bill parsing and payment result parsing.
- `mobile/bcn_restaurant_mobile/test/features/cashier/cashier_repository_test.dart` — exact GET/POST API contracts.
- `mobile/bcn_restaurant_mobile/test/features/cashier/cashier_screen_test.dart` — Open/Billing action behavior and success refresh.
- `mobile/bcn_restaurant_mobile/test/features/printing/windows_print_repository_test.dart` — exact `bcn_cashier_print_bill` contract.

### Docs

- `docs/server-script-mobile.md` — aliases, required custom fields/configuration, deployment and smoke-test instructions.

---

## Preflight Gate 0: Prove OurCity Safe-Exec Printing and Locking

This gate happens before production cashier code is written. The approved architecture requires Server Script safe execution to support all four primitives: `SELECT ... FOR UPDATE`, `frappe.get_print`, PDF-to-base64 conversion, and realtime publication. If any required primitive is unavailable on OurCity, stop implementation and return to design; do not silently switch to custom-app installation or a different transport.

Create a temporary Frappe **Server Script**, Script Type `API`, API Method `bcn_cashier_capability_probe`, with this body:

```python
sales_order = (frappe.form_dict.get("sales_order") or "").strip()
if not sales_order:
    frappe.throw("sales_order is required")

rows = frappe.db.sql(
    """
    SELECT name
    FROM `tabSales Order`
    WHERE name = %(sales_order)s
    FOR UPDATE
    """,
    {"sales_order": sales_order},
    as_dict=True,
)
if not rows:
    frappe.throw("Sales Order not found")

pdf = frappe.get_print(
    "Sales Order",
    sales_order,
    print_format="Standard",
    as_pdf=True,
)
pdf_base64 = frappe.utils.pdf_to_base64(pdf)

publish_error = ""
try:
    frappe.publish_realtime(
        "document_print_event",
        {
            "doctype": "Sales Order",
            "document_name": sales_order,
            "method": "probe",
            "jobs": [],
        },
        after_commit=True,
    )
except Exception as exc:
    publish_error = str(exc)

frappe.response["message"] = {
    "lock_rows": len(rows),
    "pdf_base64_length": len(pdf_base64 or ""),
    "publish_error": publish_error,
}
```

- [ ] **Step 1: Pick an existing Draft Sales Order name on OurCity**

Use the same controlled table/order that will later be used for cashier smoke testing.

- [ ] **Step 2: Call the capability probe**

Run in PowerShell with the already authenticated `$FrappeSession`:

```powershell
$so = "SAL-ORD-2026-00001"
Invoke-RestMethod `
  -Uri "https://ourcity.s.frappe.cloud/api/method/bcn_cashier_capability_probe" `
  -Method Post `
  -WebSession $FrappeSession `
  -Body @{ sales_order = $so } `
  -ContentType "application/x-www-form-urlencoded" |
ConvertTo-Json -Depth 10
```

Expected response requirements:

```text
message.lock_rows = 1
message.pdf_base64_length > 100
message.publish_error = ""
```

- [ ] **Step 3: Gate the rest of the plan**

If `publish_error` is non-empty, PDF conversion fails, or the lock query is rejected, stop here and report the exact OurCity error. Do not execute Tasks 1-7 until the design is revised.

If all three checks pass, disable/delete the temporary capability Server Script and continue.

---

### Task 1: Keep Draft Sales Order Taxes and Totals Stable During Waiter Updates

**Files:**
- Modify: `server_scripts/mobile/create_order.py`
- Modify: `tests/test_ourcity_server_script_contract.py`

**Interfaces:**
- Consumes: POS Profile `DMT.taxes_and_charges`; existing waiter payload and Draft Sales Order reuse logic.
- Produces: every Open Draft Sales Order has the DMT tax template applied and recalculated before save; cashier can treat its totals as the frozen bill source.

- [ ] **Step 1: Write the failing contract test**

Add to `tests/test_ourcity_server_script_contract.py`:

```python
def test_create_order_applies_and_recalculates_dmt_taxes():
    source = _read(SERVER_SCRIPTS / "create_order.py")
    assert "profile.taxes_and_charges" in source
    assert "sales_order.taxes_and_charges" in source
    assert "sales_order.set_taxes()" in source
    assert "sales_order.calculate_taxes_and_totals()" in source
```

- [ ] **Step 2: Run the test and verify RED**

Run from repository root:

```powershell
python -m pytest tests/test_ourcity_server_script_contract.py::test_create_order_applies_and_recalculates_dmt_taxes -q
```

Expected: FAIL because current `create_order.py` does not apply DMT taxes.

- [ ] **Step 3: Add tax-template initialization to new Draft Sales Orders**

In `server_scripts/mobile/create_order.py`, after loading `profile` and while initializing a new Sales Order, add:

```python
if profile.taxes_and_charges:
    sales_order.taxes_and_charges = profile.taxes_and_charges
    sales_order.set_taxes()
```

- [ ] **Step 4: Recalculate totals after all item mutations**

Immediately before setting `custom_client_order_id` and saving, add:

```python
if profile.taxes_and_charges and not sales_order.taxes_and_charges:
    sales_order.taxes_and_charges = profile.taxes_and_charges
    sales_order.set_taxes()

sales_order.calculate_taxes_and_totals()
```

Do not overwrite existing tax rows on every waiter round; reuse the existing template/rows and recalculate against the new item quantities.

- [ ] **Step 5: Run the contract test GREEN**

```powershell
python -m pytest tests/test_ourcity_server_script_contract.py::test_create_order_applies_and_recalculates_dmt_taxes -q
```

Expected: PASS.

- [ ] **Step 6: Run the existing waiter/server-script regression set**

```powershell
python -m pytest tests/test_ourcity_server_script_contract.py tests/test_mobile_without_kitchen_monitor.py -q
```

Expected: all tests PASS.

- [ ] **Step 7: Commit**

```powershell
git add server_scripts/mobile/create_order.py tests/test_ourcity_server_script_contract.py
git commit -m "feat: keep restaurant draft totals aligned with DMT taxes"
```

---

### Task 2: Add Cashier GET Billing List for Open/Billing Draft Sales Orders

**Files:**
- Create: `server_scripts/mobile/cashier_billing.py`
- Modify: `tests/test_ourcity_server_script_contract.py`

**Interfaces:**
- Consumes: `Sales Order.custom_restaurant_status`, POS Profile `DMT`, Customer, Sales Order Item, Sales Taxes and Charges.
- Produces: `bcn_cashier_billing` GET response with `bills` and `modes`.

Exact response contract:

```json
{
  "bills": [
    {
      "sales_order": "SAL-ORD-2026-00001",
      "customer": "Table 01",
      "customer_name": "Table 01",
      "creation": "2026-09-07 10:00:00",
      "net_total": 10000,
      "total_taxes_and_charges": 500,
      "grand_total": 10500,
      "currency": "MMK",
      "restaurant_status": "Open",
      "items": [],
      "taxes": []
    }
  ],
  "modes": [
    {"name": "Cash", "default": true},
    {"name": "Kpay", "default": false}
  ]
}
```

- [ ] **Step 1: Write the failing server-script contract test**

Add:

```python
def test_cashier_billing_lists_open_and_billing_draft_sales_orders():
    path = SERVER_SCRIPTS / "cashier_billing.py"
    assert path.exists()
    source = _read(path)
    assert 'POS_PROFILE = "DMT"' in source
    assert '"docstatus": 0' in source
    assert '["Open", "Billing"]' in source
    assert '"bills"' in source
    assert '"modes"' in source
    assert "Restaurant Table Session" not in source
    assert "Sales Invoice" not in source.split('action == "Pay"')[0]
```

- [ ] **Step 2: Run RED**

```powershell
python -m pytest tests/test_ourcity_server_script_contract.py::test_cashier_billing_lists_open_and_billing_draft_sales_orders -q
```

Expected: FAIL because `cashier_billing.py` does not exist.

- [ ] **Step 3: Create the GET/list half of `cashier_billing.py`**

Start the file with the same fixed OurCity constants and role pattern used by the existing Server Script mirrors:

```python
COMPANY = "Doh Myot Daw BBQ & Restaurant"
POS_PROFILE = "DMT"
PRICE_LIST = "Standard Selling"
CURRENCY = "MMK"

current_user = frappe.session.user
if not current_user or current_user == "Guest":
    frappe.throw("Authentication is required.")

role_rows = frappe.get_all(
    "Has Role",
    filters={"parent": current_user, "parenttype": "User"},
    fields=["role"],
    limit_page_length=200,
)
roles = [row.role for row in role_rows if row.role]
allowed = (
    current_user == "Administrator"
    or "System Manager" in roles
    or "Restaurant Manager" in roles
    or "Cashier" in roles
)
if not allowed:
    frappe.throw("You are not allowed to use cashier billing.")

action = (frappe.form_dict.get("action") or "").strip()
```

For `action == ""`, query Draft Sales Orders only:

```python
orders = frappe.get_all(
    "Sales Order",
    filters={
        "company": COMPANY,
        "docstatus": 0,
        "custom_restaurant_status": ["in", ["Open", "Billing"]],
    },
    fields=[
        "name",
        "customer",
        "creation",
        "net_total",
        "total_taxes_and_charges",
        "grand_total",
        "currency",
        "custom_restaurant_status",
    ],
    order_by="creation asc",
    limit_page_length=500,
)
```

For each Sales Order, load the document and emit item rows with:

```text
item_code, item_name, qty, rate, amount, warehouse, kitchen_counter
```

and tax rows with:

```text
description/account_head, rate, tax_amount, charge_type
```

Read payment modes from `frappe.get_doc("POS Profile", POS_PROFILE).payments`, include each non-empty `mode_of_payment`, and set `default` from the POS Profile payment row.

Return only:

```python
frappe.response["message"] = {"bills": bills, "modes": modes}
```

- [ ] **Step 4: Run GREEN**

```powershell
python -m pytest tests/test_ourcity_server_script_contract.py::test_cashier_billing_lists_open_and_billing_draft_sales_orders -q
```

Expected: PASS.

- [ ] **Step 5: Deploy/update API Server Script `bcn_cashier_billing` on OurCity and smoke GET**

```powershell
Invoke-RestMethod `
  -Uri "https://ourcity.s.frappe.cloud/api/method/bcn_cashier_billing" `
  -Method Get `
  -WebSession $FrappeSession |
ConvertTo-Json -Depth 20
```

Expected for an occupied test table: at least one `bills` row with `restaurant_status` `Open` or `Billing`; no Sales Invoice is created by this GET.

- [ ] **Step 6: Commit**

```powershell
git add server_scripts/mobile/cashier_billing.py tests/test_ourcity_server_script_contract.py
git commit -m "feat: list draft restaurant bills for cashier"
```

---

### Task 3: Add Draft Sales Order Cashier Print Endpoint

**Files:**
- Create: `server_scripts/mobile/cashier_print_bill.py`
- Modify: `tests/test_ourcity_server_script_contract.py`

**Interfaces:**
- Consumes: POST `{sales_order}`, POS Profile `DMT.custom_cashier_printer`, `DMT.custom_cashier_print_format`.
- Produces: `bcn_cashier_print_bill` response `{sales_order, status: "accepted", is_reprint}` and one `document_print_event` with a Sales Order PDF job.

- [ ] **Step 1: Write the failing print contract test**

Add:

```python
def test_cashier_print_bill_freezes_and_prints_draft_sales_order():
    path = SERVER_SCRIPTS / "cashier_print_bill.py"
    assert path.exists()
    source = _read(path)
    assert 'custom_restaurant_status = "Billing"' in source
    assert "FOR UPDATE" in source
    assert 'frappe.get_print(' in source
    assert "frappe.utils.pdf_to_base64" in source
    assert '"document_print_event"' in source
    assert "after_commit=True" in source
    assert 'custom_cashier_printer' in source
    assert 'custom_cashier_print_format' in source
    assert '"status": "accepted"' in source
    assert "Sales Invoice" not in source
```

- [ ] **Step 2: Run RED**

```powershell
python -m pytest tests/test_ourcity_server_script_contract.py::test_cashier_print_bill_freezes_and_prints_draft_sales_order -q
```

Expected: FAIL because the file does not exist.

- [ ] **Step 3: Implement role/input validation and row lock**

Use the same cashier role check as Task 2, then:

```python
sales_order_name = (frappe.form_dict.get("sales_order") or "").strip()
if not sales_order_name:
    frappe.throw("sales_order is required")

locked = frappe.db.sql(
    """
    SELECT name, docstatus, custom_restaurant_status, company
    FROM `tabSales Order`
    WHERE name = %(name)s
    FOR UPDATE
    """,
    {"name": sales_order_name},
    as_dict=True,
)
if not locked:
    frappe.throw("Sales Order not found")

row = locked[0]
if row.docstatus != 0:
    frappe.throw("Only Draft restaurant Sales Orders can be printed")
if row.company != COMPANY:
    frappe.throw("Sales Order is outside the restaurant company")
if row.custom_restaurant_status not in ("Open", "Billing"):
    frappe.throw("Sales Order is not active for cashier billing")

is_reprint = row.custom_restaurant_status == "Billing"
```

- [ ] **Step 4: Validate cashier printer configuration**

Load POS Profile `DMT` and require:

```python
printer = (profile.get("custom_cashier_printer") or "").strip()
print_format = (profile.get("custom_cashier_print_format") or "").strip()
if not printer:
    frappe.throw("DMT cashier printer is not configured")
if not print_format:
    frappe.throw("DMT cashier Sales Order print format is not configured")

print_doctype = frappe.db.get_value("Print Format", print_format, "doc_type")
if print_doctype != "Sales Order":
    frappe.throw("DMT cashier print format must be for Sales Order")
```

- [ ] **Step 5: Freeze, render, convert, and publish**

```python
sales_order = frappe.get_doc("Sales Order", sales_order_name)
if not is_reprint:
    sales_order.custom_restaurant_status = "Billing"
    sales_order.save(ignore_permissions=True)

pdf = frappe.get_print(
    "Sales Order",
    sales_order.name,
    print_format=print_format,
    as_pdf=True,
    doc=sales_order,
)
pdf_base64 = frappe.utils.pdf_to_base64(pdf)

frappe.publish_realtime(
    "document_print_event",
    {
        "doctype": "Sales Order",
        "document_name": sales_order.name,
        "method": "manual",
        "jobs": [
            {
                "doctype": "Sales Order",
                "document_name": sales_order.name,
                "invoice_name": sales_order.name,
                "printer": printer,
                "is_cashier": True,
                "print_format": print_format,
                "pdf_base64": pdf_base64,
            }
        ],
    },
    after_commit=True,
)

frappe.response["message"] = {
    "sales_order": sales_order.name,
    "status": "accepted",
    "is_reprint": is_reprint,
}
```

Do not catch and suppress render/publish errors. An exception must abort the request so an Open -> Billing change rolls back before commit.

- [ ] **Step 6: Run GREEN and full contract regressions**

```powershell
python -m pytest tests/test_ourcity_server_script_contract.py -q
```

Expected: all tests PASS.

- [ ] **Step 7: Deploy `bcn_cashier_print_bill` and live test Open -> Billing**

```powershell
Invoke-RestMethod `
  -Uri "https://ourcity.s.frappe.cloud/api/method/bcn_cashier_print_bill" `
  -Method Post `
  -WebSession $FrappeSession `
  -Body @{ sales_order = $so } `
  -ContentType "application/x-www-form-urlencoded" |
ConvertTo-Json -Depth 10
```

Expected first call: `status=accepted`, `is_reprint=false`, table changes to Billing, Windows app receives `document_print_event`.

Call the same endpoint again. Expected: `is_reprint=true`; Sales Order remains Billing.

- [ ] **Step 8: Commit**

```powershell
git add server_scripts/mobile/cashier_print_bill.py tests/test_ourcity_server_script_contract.py
git commit -m "feat: print draft sales order cashier bills"
```

---

### Task 4: Add Atomic Payment Finalization and Retry Resolution

**Files:**
- Modify: `server_scripts/mobile/cashier_billing.py`
- Modify: `tests/test_ourcity_server_script_contract.py`

**Interfaces:**
- Consumes: POST `action=Pay`, `sales_order`, JSON `payments`.
- Produces: `{sales_order, sales_invoice, payment_entries, change_amount, duplicate}`.
- Retry identity: submitted Sales Invoice Items whose `sales_order` equals the submitted Closed Sales Order.

- [ ] **Step 1: Write failing payment/finalization contract tests**

Add:

```python
def test_cashier_payment_uses_sales_order_update_stock_and_closed_state():
    source = _read(SERVER_SCRIPTS / "cashier_billing.py")
    assert 'action == "Pay"' in source
    assert "FOR UPDATE" in source
    assert 'sales_order_name = (frappe.form_dict.get("sales_order")' in source
    assert "json.loads" in source
    assert 'sales_order.custom_restaurant_status = "Closed"' in source
    assert "sales_order.submit()" in source
    assert 'sales_invoice.update_stock = 1' in source
    assert '"sales_order": sales_order.name' in source
    assert '"so_detail": item.name' in source
    assert "Payment Entry" in source
    assert "outstanding_amount" in source
    assert "frappe.db.commit" not in source
    assert "frappe.db.rollback" not in source


def test_cashier_payment_has_retry_and_amount_consistency_guards():
    source = _read(SERVER_SCRIPTS / "cashier_billing.py")
    assert "Sales Invoice Item" in source
    assert "Payment Entry Reference" in source
    assert "duplicate" in source
    assert "net_total" in source
    assert "total_taxes_and_charges" in source
    assert "grand_total" in source
    assert "ROUNDING_TOLERANCE" in source
```

- [ ] **Step 2: Run RED**

```powershell
python -m pytest tests/test_ourcity_server_script_contract.py::test_cashier_payment_uses_sales_order_update_stock_and_closed_state tests/test_ourcity_server_script_contract.py::test_cashier_payment_has_retry_and_amount_consistency_guards -q
```

Expected: FAIL because the Pay branch is not implemented.

- [ ] **Step 3: Parse and validate payment tenders before document submission**

Use:

```python
ROUNDING_TOLERANCE = 0.01

sales_order_name = (frappe.form_dict.get("sales_order") or "").strip()
raw_payments = frappe.form_dict.get("payments")
payments = json.loads(raw_payments) if raw_payments else []
if not sales_order_name:
    frappe.throw("sales_order is required")
if not payments:
    frappe.throw("At least one payment is required")
```

Build allowed modes from `profile.payments`. For each tender require a configured mode and `amount > 0`. Resolve mode type using:

```python
mode_type = frappe.db.get_value("Mode of Payment", mode, "type") or ""
account = frappe.db.get_value(
    "Mode of Payment Account",
    {"parent": mode, "company": COMPANY},
    "default_account",
)
if not account:
    frappe.throw("No company account configured for Mode of Payment " + mode)
```

Compute:

```text
non_cash_total <= amount_due
cash may exceed remaining amount
usable allocations sum exactly to amount_due within 0.01
change_amount = total_tendered - amount_due when excess is Cash
```

Create no zero-value allocations.

- [ ] **Step 4: Lock the Sales Order and resolve successful retries before creating anything**

Lock using `SELECT ... FOR UPDATE` by Sales Order name.

If `docstatus == 1` and `custom_restaurant_status == "Closed"`, find submitted invoice-item rows:

```python
invoice_item_rows = frappe.get_all(
    "Sales Invoice Item",
    filters={"sales_order": sales_order_name, "docstatus": 1},
    fields=["parent"],
    limit_page_length=100,
)
invoice_names = []
for row in invoice_item_rows:
    if row.parent and row.parent not in invoice_names:
        invoice_names.append(row.parent)
```

Require exactly one `invoice_names` entry. Then find submitted `Payment Entry Reference` rows for that Sales Invoice, collect unique parents, and return:

```python
frappe.response["message"] = {
    "sales_order": sales_order_name,
    "sales_invoice": invoice_names[0],
    "payment_entries": payment_entry_names,
    "change_amount": 0,
    "duplicate": True,
}
```

If submitted/Closed has zero or multiple linked submitted Sales Invoices, throw a conflict error instead of guessing.

- [ ] **Step 5: Freeze totals, set Closed in-memory, and submit the Sales Order**

For active Draft Open/Billing orders only:

```python
sales_order = frappe.get_doc("Sales Order", sales_order_name)
if sales_order.custom_restaurant_status not in ("Open", "Billing"):
    frappe.throw("Sales Order is not active for cashier payment")

frozen_net_total = frappe.utils.flt(sales_order.net_total)
frozen_taxes = frappe.utils.flt(sales_order.total_taxes_and_charges)
frozen_grand_total = frappe.utils.flt(sales_order.grand_total)

sales_order.custom_restaurant_status = "Closed"
sales_order.flags.ignore_permissions = True
sales_order.submit()
```

Do not commit here.

- [ ] **Step 6: Create one linked Sales Invoice with Update Stock**

Create the invoice directly with safe Server Script APIs:

```python
sales_invoice = frappe.new_doc("Sales Invoice")
sales_invoice.company = COMPANY
sales_invoice.customer = sales_order.customer
sales_invoice.posting_date = frappe.utils.nowdate()
sales_invoice.due_date = frappe.utils.nowdate()
sales_invoice.selling_price_list = sales_order.selling_price_list or PRICE_LIST
sales_invoice.price_list_currency = sales_order.price_list_currency or CURRENCY
sales_invoice.currency = sales_order.currency or CURRENCY
sales_invoice.conversion_rate = sales_order.conversion_rate or 1
sales_invoice.plc_conversion_rate = sales_order.plc_conversion_rate or 1
sales_invoice.pos_profile = POS_PROFILE
sales_invoice.update_stock = 1

for item in sales_order.items:
    sales_invoice.append(
        "items",
        {
            "item_code": item.item_code,
            "item_name": item.item_name,
            "description": item.description,
            "qty": item.qty,
            "uom": item.uom,
            "stock_uom": item.stock_uom,
            "conversion_factor": item.conversion_factor or 1,
            "rate": item.rate,
            "warehouse": item.warehouse or sales_order.set_warehouse or profile.warehouse,
            "sales_order": sales_order.name,
            "so_detail": item.name,
        },
    )
```

Copy the frozen tax template and tax rows:

```python
sales_invoice.taxes_and_charges = sales_order.taxes_and_charges
for tax in sales_order.taxes:
    sales_invoice.append(
        "taxes",
        {
            "charge_type": tax.charge_type,
            "account_head": tax.account_head,
            "description": tax.description,
            "rate": tax.rate,
            "tax_amount": tax.tax_amount,
            "included_in_print_rate": tax.included_in_print_rate,
            "included_in_paid_amount": tax.included_in_paid_amount,
            "cost_center": tax.cost_center,
            "row_id": tax.row_id,
        },
    )

sales_invoice.flags.ignore_permissions = True
sales_invoice.insert(ignore_permissions=True)
```

- [ ] **Step 7: Compare final invoice totals before submission**

```python
if abs(frappe.utils.flt(sales_invoice.net_total) - frozen_net_total) > ROUNDING_TOLERANCE:
    frappe.throw("Sales Invoice Net Total does not match the frozen bill")
if abs(frappe.utils.flt(sales_invoice.total_taxes_and_charges) - frozen_taxes) > ROUNDING_TOLERANCE:
    frappe.throw("Sales Invoice taxes do not match the frozen bill")
if abs(frappe.utils.flt(sales_invoice.grand_total) - frozen_grand_total) > ROUNDING_TOLERANCE:
    frappe.throw("Sales Invoice Grand Total does not match the frozen bill")

sales_invoice.submit()
```

Any mismatch must throw and roll back the entire request.

- [ ] **Step 8: Create one Payment Entry per positive usable allocation**

For each `(mode, allocated_amount, account)` allocation:

```python
payment_entry = frappe.new_doc("Payment Entry")
payment_entry.payment_type = "Receive"
payment_entry.company = COMPANY
payment_entry.posting_date = frappe.utils.nowdate()
payment_entry.mode_of_payment = mode
payment_entry.party_type = "Customer"
payment_entry.party = sales_invoice.customer
payment_entry.paid_from = sales_invoice.debit_to
payment_entry.paid_to = account
payment_entry.paid_amount = allocated_amount
payment_entry.received_amount = allocated_amount
payment_entry.reference_no = sales_order.name
payment_entry.reference_date = frappe.utils.nowdate()
payment_entry.append(
    "references",
    {
        "reference_doctype": "Sales Invoice",
        "reference_name": sales_invoice.name,
        "total_amount": sales_invoice.grand_total,
        "outstanding_amount": sales_invoice.outstanding_amount,
        "allocated_amount": allocated_amount,
    },
)
payment_entry.flags.ignore_permissions = True
payment_entry.insert(ignore_permissions=True)
payment_entry.submit()
```

Collect each submitted Payment Entry name.

- [ ] **Step 9: Verify final outstanding and return result**

Read current outstanding from the database:

```python
outstanding = frappe.utils.flt(
    frappe.db.get_value("Sales Invoice", sales_invoice.name, "outstanding_amount")
)
if abs(outstanding) > ROUNDING_TOLERANCE:
    frappe.throw("Sales Invoice is not fully settled")

frappe.response["message"] = {
    "sales_order": sales_order.name,
    "sales_invoice": sales_invoice.name,
    "payment_entries": payment_entry_names,
    "change_amount": change_amount,
    "duplicate": False,
}
```

- [ ] **Step 10: Run GREEN and regressions**

```powershell
python -m pytest tests/test_ourcity_server_script_contract.py tests/test_mobile_without_kitchen_monitor.py -q
```

Expected: all tests PASS.

- [ ] **Step 11: Deploy updated `bcn_cashier_billing` but do not run destructive live payment until Flutter contract tasks are ready**

Verify GET still works after deployment.

- [ ] **Step 12: Commit**

```powershell
git add server_scripts/mobile/cashier_billing.py tests/test_ourcity_server_script_contract.py
git commit -m "feat: finalize restaurant bills atomically"
```

---

### Task 5: Replace Flutter Invoice-First Cashier Models and API Contracts

**Files:**
- Modify: `mobile/bcn_restaurant_mobile/lib/features/cashier/domain/cashier_models.dart`
- Modify: `mobile/bcn_restaurant_mobile/lib/features/cashier/data/cashier_repository.dart`
- Create: `mobile/bcn_restaurant_mobile/lib/features/printing/domain/cashier_bill_print_result.dart`
- Modify: `mobile/bcn_restaurant_mobile/lib/features/printing/data/windows_print_repository.dart`
- Create: `mobile/bcn_restaurant_mobile/test/features/cashier/cashier_models_test.dart`
- Create: `mobile/bcn_restaurant_mobile/test/features/cashier/cashier_repository_test.dart`
- Modify: `mobile/bcn_restaurant_mobile/test/features/printing/windows_print_repository_test.dart`

**Interfaces:**
- Produces `CashierBill`, `CashierBillingResponse`, `CashierPaymentResult`, `CashierBillPrintResult`.
- `CashierGateway.getBilling()` -> `Future<CashierBillingResponse>`.
- `CashierGateway.paySplit({required String salesOrder, required List<CashierPaymentTender> payments})` -> `Future<CashierPaymentResult>`.
- `WindowsPrintGateway.requestCashierBill(String salesOrder)` -> `Future<CashierBillPrintResult>`.

- [ ] **Step 1: Write failing model tests**

Create `cashier_models_test.dart` with fixtures matching the approved API:

```dart
import 'package:bcn_restaurant_mobile/features/cashier/domain/cashier_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses an Open Draft Sales Order cashier bill', () {
    final response = CashierBillingResponse.fromJson({
      'bills': [
        {
          'sales_order': 'SAL-ORD-2026-00001',
          'customer': 'Table 01',
          'customer_name': 'Table 01',
          'creation': '2026-09-07 10:00:00',
          'net_total': 10000,
          'total_taxes_and_charges': 500,
          'grand_total': 10500,
          'currency': 'MMK',
          'restaurant_status': 'Open',
          'items': [],
          'taxes': [],
        },
      ],
      'modes': [
        {'name': 'Cash', 'default': true},
      ],
    });

    expect(response.bills.single.salesOrder, 'SAL-ORD-2026-00001');
    expect(response.bills.single.restaurantStatus, 'Open');
    expect(response.bills.single.grandTotal, 10500);
    expect(response.modes.single.name, 'Cash');
  });

  test('parses final payment result', () {
    final result = CashierPaymentResult.fromJson({
      'sales_order': 'SAL-ORD-2026-00001',
      'sales_invoice': 'ACC-SINV-2026-00001',
      'payment_entries': ['ACC-PAY-2026-00001'],
      'change_amount': 1000,
      'duplicate': false,
    });

    expect(result.salesInvoice, 'ACC-SINV-2026-00001');
    expect(result.paymentEntries, ['ACC-PAY-2026-00001']);
    expect(result.changeAmount, 1000);
    expect(result.duplicate, isFalse);
  });
}
```

- [ ] **Step 2: Write failing repository/printing contract tests**

In `cashier_repository_test.dart`, record calls and require:

```dart
expect(api.getCalls.single.method, 'bcn_cashier_billing');
```

and for payment:

```dart
expect(api.postCalls.single.method, 'bcn_cashier_billing');
expect(api.postCalls.single.data?['action'], 'Pay');
expect(api.postCalls.single.data?['sales_order'], 'SAL-ORD-2026-00001');
expect(api.postCalls.single.data?['payments'], isA<String>());
```

Update `windows_print_repository_test.dart` so the cashier print test requires:

```dart
expect(api.postCalls.single.method, 'bcn_cashier_print_bill');
expect(api.postCalls.single.data, {'sales_order': 'SAL-ORD-2026-00001'});
expect(result.status, 'accepted');
expect(result.isReprint, isFalse);
```

- [ ] **Step 3: Run RED**

From `mobile/bcn_restaurant_mobile`:

```powershell
flutter test test/features/cashier/cashier_models_test.dart test/features/cashier/cashier_repository_test.dart test/features/printing/windows_print_repository_test.dart
```

Expected: FAIL because the new bill/result contracts do not exist.

- [ ] **Step 4: Replace invoice-first models with bill-first models**

Keep `CashierPaymentTender` and `CashierPaymentMode`. Replace invoice-specific aggregate classes with:

```dart
class CashierBill {
  const CashierBill({
    required this.salesOrder,
    required this.customer,
    required this.customerName,
    required this.creation,
    required this.netTotal,
    required this.totalTaxesAndCharges,
    required this.grandTotal,
    required this.currency,
    required this.restaurantStatus,
    required this.items,
    required this.taxes,
  });

  final String salesOrder;
  final String customer;
  final String customerName;
  final String? creation;
  final double netTotal;
  final double totalTaxesAndCharges;
  final double grandTotal;
  final String currency;
  final String restaurantStatus;
  final List<CashierBillItem> items;
  final List<CashierBillTax> taxes;

  bool get isBilling => restaurantStatus == 'Billing';
}
```

Define `CashierBillItem` from `item_code`, `item_name`, `qty`, `rate`, `amount`, `warehouse`, `kitchen_counter`; define `CashierBillTax` from `description/account_head`, `rate`, `tax_amount`, `charge_type`.

Change `CashierBillingResponse` to contain only:

```dart
final List<CashierBill> bills;
final List<CashierPaymentMode> modes;
```

Add:

```dart
class CashierPaymentResult {
  const CashierPaymentResult({
    required this.salesOrder,
    required this.salesInvoice,
    required this.paymentEntries,
    required this.changeAmount,
    required this.duplicate,
  });
  // fromJson uses sales_order, sales_invoice, payment_entries,
  // change_amount, duplicate.
}
```

- [ ] **Step 5: Add `CashierGateway` and change repository request fields**

In `cashier_repository.dart`:

```dart
abstract interface class CashierGateway {
  Future<CashierBillingResponse> getBilling();

  Future<CashierPaymentResult> paySplit({
    required String salesOrder,
    required List<CashierPaymentTender> payments,
  });
}

class CashierRepository implements CashierGateway {
  const CashierRepository(this._apiClient);
  // ...
}
```

Remove invoice-only compatibility methods `recordBillPrint` and `pay`.

`paySplit` must POST:

```dart
{
  'action': 'Pay',
  'sales_order': salesOrder,
  'payments': jsonEncode(
    payments.map((tender) => {
      'mode_of_payment': tender.modeOfPayment,
      'amount': tender.amount,
    }).toList(),
  ),
}
```

- [ ] **Step 6: Add the Server Script print result and update Windows print gateway**

Create `cashier_bill_print_result.dart`:

```dart
class CashierBillPrintResult {
  const CashierBillPrintResult({
    required this.salesOrder,
    required this.status,
    required this.isReprint,
  });

  factory CashierBillPrintResult.fromJson(Map<String, dynamic> json) {
    return CashierBillPrintResult(
      salesOrder: json['sales_order']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      isReprint: json['is_reprint'] == true || json['is_reprint'] == 1,
    );
  }

  final String salesOrder;
  final String status;
  final bool isReprint;
}
```

Change only the cashier request method in `WindowsPrintGateway`:

```dart
Future<CashierBillPrintResult> requestCashierBill(String salesOrder);
```

and call:

```dart
final data = await _apiClient.postMethod(
  'bcn_cashier_print_bill',
  data: {'sales_order': salesOrder},
);
```

Leave status/retry methods intact for existing settings screens, but the cashier screen must no longer depend on them.

- [ ] **Step 7: Run GREEN**

```powershell
flutter test test/features/cashier/cashier_models_test.dart test/features/cashier/cashier_repository_test.dart test/features/printing/windows_print_repository_test.dart
```

Expected: all selected tests PASS.

- [ ] **Step 8: Commit**

```powershell
git add mobile/bcn_restaurant_mobile/lib/features/cashier mobile/bcn_restaurant_mobile/lib/features/printing mobile/bcn_restaurant_mobile/test/features/cashier mobile/bcn_restaurant_mobile/test/features/printing/windows_print_repository_test.dart
git commit -m "refactor: use sales order cashier contracts"
```

---

### Task 6: Update Cashier Screen for Open/Billing Print and Payment

**Files:**
- Modify: `mobile/bcn_restaurant_mobile/lib/features/cashier/presentation/cashier_screen.dart`
- Create: `mobile/bcn_restaurant_mobile/test/features/cashier/cashier_screen_test.dart`

**Interfaces:**
- Consumes: `CashierGateway`, `WindowsPrintGateway`, `CashierBill`.
- Produces: Open card -> Print Bill + Payment; Billing card -> Reprint Bill + Payment; payment success refreshes cashier and both table providers.

- [ ] **Step 1: Write failing widget tests for Open and Billing actions**

Use fake `CashierGateway` and `WindowsPrintGateway` provider overrides. Build one Open `CashierBill`, pump `CashierScreen`, and assert:

```dart
expect(find.text('Print Bill'), findsOneWidget);
expect(find.text('Payment'), findsOneWidget);
expect(find.text('Open'), findsOneWidget);
```

Build one Billing bill and assert:

```dart
expect(find.text('Reprint Bill'), findsOneWidget);
expect(find.text('Payment'), findsOneWidget);
expect(find.text('Billing'), findsOneWidget);
```

- [ ] **Step 2: Write failing print interaction test**

Tap `Print Bill` and verify fake print gateway received exactly:

```text
SAL-ORD-2026-00001
```

After accepted response, verify `cashierBillingProvider` is refreshed and snackbar text contains `Print request accepted`.

Do not expect a print job ID or `View status` action.

- [ ] **Step 3: Write failing payment success refresh test**

Use one Cash mode, open the payment sheet, enter/accept the full amount, tap `Confirm Payment`, return a fake `CashierPaymentResult`, and verify:

```text
cashier billing refresh requested
dine_in tables refresh requested
takeaway tables refresh requested
```

The success snackbar must mention the Sales Invoice name and any positive change amount.

- [ ] **Step 4: Run RED**

```powershell
flutter test test/features/cashier/cashier_screen_test.dart
```

Expected: FAIL because the screen still expects invoice-first fields and old print result context.

- [ ] **Step 5: Change screen providers to the gateway interfaces**

Keep:

```dart
final cashierRepositoryProvider = Provider<CashierGateway>(
  (ref) => CashierRepository(ref.watch(apiClientProvider)),
);
```

`cashierBillingProvider` still calls `getBilling()`.

- [ ] **Step 6: Render `data.bills` instead of `data.invoices`**

Search continues to use customer/table name and Sales Order number. Replace invoice status/payment fields with:

```text
bill.salesOrder
bill.restaurantStatus
bill.grandTotal
```

The amount due before finalization is `bill.grandTotal`.

- [ ] **Step 7: Replace print flow with Sales Order accepted/reprint flow**

Call:

```dart
final result = await repository.requestCashierBill(bill.salesOrder);
```

On success:

```dart
ref.invalidate(cashierBillingProvider);
ref.invalidate(tablesProvider('dine_in'));
ref.invalidate(tablesProvider('takeaway'));
```

Show `Print request accepted` or `Reprint request accepted`. Remove the `KnownPrintJobContext`, retained-job state, job ID display, and `View status` action from this cashier path.

- [ ] **Step 8: Replace payment call with Sales Order input**

Call:

```dart
final result = await ref.read(cashierRepositoryProvider).paySplit(
  salesOrder: bill.salesOrder,
  payments: tenders,
);
```

On success, invalidate the same three providers and show the returned `salesInvoice`, Payment Entry names, and `changeAmount`.

Keep existing tender UI rules:

```text
non-cash cannot exceed amount due
change requires Cash
Split auto-balances primary Cash against secondary mode
```

- [ ] **Step 9: Run GREEN and Flutter regression suite**

```powershell
flutter test test/features/cashier/cashier_screen_test.dart
flutter test
flutter analyze
```

Expected: all tests PASS and analyzer reports no errors.

- [ ] **Step 10: Commit**

```powershell
git add mobile/bcn_restaurant_mobile/lib/features/cashier/presentation/cashier_screen.dart mobile/bcn_restaurant_mobile/test/features/cashier/cashier_screen_test.dart
git commit -m "feat: drive cashier ui from draft sales orders"
```

---

### Task 7: Update Deployment Docs and Run End-to-End OurCity Acceptance

**Files:**
- Modify: `docs/server-script-mobile.md`
- Modify: `tests/test_ourcity_server_script_contract.py`

**Interfaces:**
- Documents: `bcn_cashier_billing`, `bcn_cashier_print_bill`, DMT cashier printer fields, payment modes/accounts, Draft SO -> SI/Payment flow.

- [ ] **Step 1: Write failing documentation contract assertions**

Extend the documentation test so it requires:

```python
assert "bcn_cashier_print_bill" in source
assert "custom_cashier_printer" in source
assert "custom_cashier_print_format" in source
assert "Update Stock" in source
assert "Delivery Note" in source
assert "Open" in source and "Billing" in source and "Closed" in source
```

- [ ] **Step 2: Run RED**

```powershell
python -m pytest tests/test_ourcity_server_script_contract.py::test_server_script_doc_describes_aliases_and_no_custom_app_requirement -q
```

Expected: FAIL until docs describe the completed cashier flow.

- [ ] **Step 3: Update `docs/server-script-mobile.md`**

Document exact aliases:

```text
bcn_mobile_bootstrap
bcn_mobile_tables
bcn_mobile_menu
bcn_mobile_create_order
bcn_cashier_billing
bcn_cashier_print_bill
```

Document required POS Profile fields:

```text
DMT.custom_cashier_printer
DMT.custom_cashier_print_format -> Print Format for Sales Order
```

Document that each DMT payment mode requires a company account, and that payment finalization is:

```text
Draft SO Billing
-> submit SO
-> Sales Invoice update_stock = 1
-> Payment Entry/Entries
-> Closed
-> Available
```

Explicitly state no Delivery Note and no custom-app installation requirement for the mobile aliases.

- [ ] **Step 4: Run GREEN and static full suite**

```powershell
python -m pytest tests/test_ourcity_server_script_contract.py tests/test_mobile_without_kitchen_monitor.py tests/test_phase3_mobile_tooling.py -q
```

Expected: all tests PASS.

- [ ] **Step 5: Configure DMT cashier printer fields before destructive smoke test**

On OurCity POS Profile `DMT` set:

```text
custom_cashier_printer = exact Windows printer system name
custom_cashier_print_format = Sales Order cashier bill print format
```

Confirm `custom_cashier_print_format` belongs to DocType `Sales Order`.

Confirm `Cash` and `Kpay` payment modes used by mobile checkout each have a Mode of Payment Account for `Doh Myot Daw BBQ & Restaurant`.

- [ ] **Step 6: Run controlled OurCity end-to-end acceptance on one table**

Use a test table and record document names at every step:

```text
1. Waiter Place Order
2. Verify same Draft SO is Open and table is Occupied
3. Cashier GET shows that Sales Order
4. Print Bill
5. Verify SO becomes Billing and Windows printer receives Draft SO bill
6. Try waiter Place Order again and verify it is rejected
7. Cashier Payment using a controlled Cash/Kpay amount
8. Verify Sales Order docstatus = 1 and custom_restaurant_status = Closed
9. Verify exactly one submitted Sales Invoice links back to that SO
10. Verify Sales Invoice update_stock = 1
11. Verify stock ledger reflects the invoice
12. Verify submitted Payment Entry/Entries reference that Sales Invoice
13. Verify Sales Invoice outstanding_amount = 0
14. Verify table returns Available
```

- [ ] **Step 7: Run retry acceptance**

Repeat the same `action=Pay` POST for the now submitted Closed Sales Order with the same payment payload.

Expected:

```text
duplicate = true
same sales_invoice name
same payment_entries names
no new Sales Invoice
no new Payment Entry
```

- [ ] **Step 8: Run reprint/offline acceptance**

For a separate Open test order, Print Bill so it becomes Billing. Stop/disable the Windows printer client after server acceptance, call Reprint Bill, and verify the Sales Order remains Billing and waiter additions remain blocked.

- [ ] **Step 9: Run final Flutter verification on the physical Android device**

```powershell
cd C:\Users\htayoolwin\bcn-restaurant-mobile\mobile\bcn_restaurant_mobile
flutter clean
flutter pub get
flutter analyze
flutter test
flutter run
```

On device verify:

```text
Open card -> Print Bill + Payment
Print -> Billing card + Reprint Bill
Billing blocks waiter order
Payment -> success snackbar
Paid card disappears
Table returns Available
```

- [ ] **Step 10: Commit docs**

```powershell
git add docs/server-script-mobile.md tests/test_ourcity_server_script_contract.py
git commit -m "docs: document cashier draft billing deployment"
```

---

## Final Verification Checklist

Run fresh after all tasks are committed:

```powershell
cd C:\Users\htayoolwin\bcn-restaurant-mobile
python -m pytest tests/test_ourcity_server_script_contract.py tests/test_mobile_without_kitchen_monitor.py tests/test_phase3_mobile_tooling.py -q

cd .\mobile\bcn_restaurant_mobile
flutter analyze
flutter test

git status
git log -10 --oneline
```

Required result:

```text
pytest: 0 failures
flutter analyze: 0 errors
flutter test: 0 failures
git status: working tree clean
branch: bcn-restaurant-mobile-without-kitchen-monitor
```

Then verify the live acceptance evidence from Task 7 shows exactly one final Sales Invoice and the expected Payment Entry identities for the controlled table order.
