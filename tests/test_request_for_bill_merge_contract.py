from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SERVER = ROOT / "server_scripts" / "mobile"
MOBILE = ROOT / "mobile" / "bcn_restaurant_mobile" / "lib" / "features"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def test_waiter_request_for_bill_submits_so_creates_draft_si_and_queues_print():
    source = read(SERVER / "request_for_bill.py")
    assert 'sales_order.custom_restaurant_status = "Billing"' in source
    assert "sales_order.submit()" in source
    assert "erpnext.selling.doctype.sales_order.sales_order.make_sales_invoice" in source
    assert "sales_invoice.insert(ignore_permissions=True)" in source
    assert "sales_invoice.submit()" not in source
    assert 'frappe.get_print(\n        "Sales Invoice"' in source
    assert 'job.status = "Pending"' in source
    assert "frappe.db.commit" not in source


def test_cashier_payment_requires_bill_requested_and_submits_existing_draft_invoice():
    source = read(SERVER / "cashier_billing.py")
    assert 'restaurant_status == "Billing"' in source
    assert "get_linked_draft_sales_invoice_names" in source
    assert "sales_invoice.submit()" in source
    assert 'frappe.db.set_value(\n            "Sales Order"' in source
    assert '"Closed"' in source
    assert "Please request the bill before taking payment" in source


def test_table_and_order_entry_keep_submitted_billing_order_locked():
    create_order = read(SERVER / "create_order.py")
    tables = read(SERVER / "tables.py")
    assert '"docstatus": ["in", [0, 1]]' in create_order
    assert "Table is currently in Billing" in create_order
    assert '"docstatus": ["in", [0, 1]]' in tables
    assert 'row.docstatus == 1 and row.custom_restaurant_status == "Billing"' in tables


def test_waiter_mobile_has_confirmed_request_for_bill_action():
    repo = read(MOBILE / "waiter_progress" / "data" / "waiter_operations_repository.dart")
    screen = read(MOBILE / "waiter_progress" / "presentation" / "waiter_progress_screen.dart")
    assert "Future<Map<String, dynamic>> requestBill" in repo
    assert "bcn_request_for_bill" in repo
    assert "Confirm Bill Request" in screen
    assert "Confirm & Print" in screen
    assert "Request for Bill" in screen


def test_cashier_keeps_existing_layout_but_disables_actions_until_billing():
    screen = read(MOBILE / "cashier" / "presentation" / "cashier_screen.dart")
    assert "final isBilling" in screen
    assert "onPressed: isBilling && !printPending ? onPrint : null" in screen
    assert "onPressed: isBilling ? onPayment : null" in screen
