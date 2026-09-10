from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SERVER = ROOT / "server_scripts" / "mobile"


def read(name: str) -> str:
    return (SERVER / name).read_text(encoding="utf-8")


def assert_cashier_invoice_print_format_is_required(source: str) -> None:
    assert 'profile.get("custom_cashier_invoice_print_format")' in source
    assert 'frappe.throw("DMT custom_cashier_invoice_print_format is required")' in source
    assert "print_format=invoice_print_format" in source
    assert "as_pdf=False" in source
    assert 'profile.get("custom_cashier_print_format")' not in source
    assert 'or "Standard"' not in source
    assert source.count("frappe.get_print(") == 1


def test_request_for_bill_requires_configured_sales_invoice_print_format():
    assert_cashier_invoice_print_format_is_required(
        read("request_for_bill.py")
    )


def test_cashier_reprint_requires_configured_sales_invoice_print_format():
    assert_cashier_invoice_print_format_is_required(
        read("cashier_print_bill.py")
    )
