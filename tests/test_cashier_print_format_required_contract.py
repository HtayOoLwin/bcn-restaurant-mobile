from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SERVER = ROOT / "server_scripts" / "mobile"


def read(name: str) -> str:
    return (SERVER / name).read_text(encoding="utf-8")


def assert_cashier_invoice_print_format_is_required(source: str) -> None:
    assert 'profile.get("custom_cashier_invoice_print_format")' in source
    assert 'frappe.throw("DMT custom_cashier_invoice_print_format is required")' in source
    assert (
        '"frappe.www.printview.get_html_and_style"'
        in source
    )
    assert "print_format=invoice_print_format" in source
    assert 'rendered.get("html")' in source
    assert 'rendered.get("style")' in source
    assert "frappe.get_print(" not in source
    assert "as_pdf=False" not in source
    assert 'profile.get("custom_cashier_print_format")' not in source
    assert 'or "Standard"' not in source


def test_request_for_bill_requires_configured_sales_invoice_print_format():
    assert_cashier_invoice_print_format_is_required(
        read("request_for_bill.py")
    )


def test_cashier_reprint_requires_configured_sales_invoice_print_format():
    assert_cashier_invoice_print_format_is_required(
        read("cashier_print_bill.py")
    )
