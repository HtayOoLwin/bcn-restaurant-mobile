from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "server_scripts"


def read(name: str) -> str:
    return (SCRIPTS / name).read_text(encoding="utf-8")


def test_request_for_bill_uses_submitted_sales_order_standard_mapper_and_durable_queue():
    source = read("bcn_request_for_bill.py")

    assert "erpnext.selling.doctype.sales_order.sales_order.make_sales_invoice" in source
    assert "custom_mobile_billing_status" in source
    assert "custom_mobile_sales_invoice" in source
    assert "Bill Requested" in source
    assert "Cashier Print Queue" in source
    assert "CASHIER|" in source
    assert "frappe.db.commit" not in source


def test_request_for_bill_is_retry_safe_and_keeps_sales_invoice_draft():
    source = read("bcn_request_for_bill.py")

    assert "docstatus" in source
    assert "sales_invoice.insert" in source
    assert "sales_invoice.submit" not in source
    assert "queue_key" in source
    assert "frappe.db.exists" in source


def test_cashier_billing_lists_ordering_and_bill_requested_and_supports_payment():
    source = read("bcn_cashier_billing.py")

    assert "Ordering" in source
    assert "Bill Requested" in source
    assert "action" in source
    assert "Pay" in source
    assert "update_stock" in source
    assert "payment_entries" in source
    assert "frappe.db.commit" not in source


def test_cashier_payment_uses_sales_order_and_linked_sales_invoice_contract():
    source = read("bcn_cashier_billing.py")

    assert 'data.get("sales_order")' in source
    assert 'data.get("sales_invoice")' in source
    assert "custom_mobile_sales_invoice" in source
    assert "payments" in source
    assert "mode_of_payment" in source


def test_cashier_setup_defines_required_fields_queue_and_settings():
    source = read("setup_cashier_billing.py")

    for token in (
        "custom_mobile_billing_status",
        "custom_bill_requested_at",
        "custom_bill_requested_by",
        "custom_mobile_sales_invoice",
        "Cashier Print Queue",
        "Cashier Print Settings",
        "printer_name",
        "queue_key",
        "Pending\\nPrinting\\nPrinted\\nError",
    ):
        assert token in source
