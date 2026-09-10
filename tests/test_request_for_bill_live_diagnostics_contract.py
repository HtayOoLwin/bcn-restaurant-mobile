import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "server_scripts" / "mobile" / "request_for_bill.py"


def test_request_for_bill_preserves_live_diagnostics_with_html_snapshot():
    source = SOURCE.read_text(encoding="utf-8")

    diagnostics = (
        "REQUEST BILL FAILED [SO LOCK]: ",
        "REQUEST BILL FAILED [SO LOAD]: ",
        "REQUEST BILL FAILED [POS PROFILE]: ",
        "REQUEST BILL FAILED [FIND DRAFT SI]: ",
        "REQUEST BILL FAILED [SI LOAD]: ",
        "REQUEST BILL FAILED [ACTIVE ORDER CHECK]: ",
        "REQUEST BILL FAILED [SO TOTALS]: ",
        "REQUEST BILL FAILED [SO SUBMIT]: ",
        "REQUEST BILL FAILED [SI BUILD]: ",
        "REQUEST BILL FAILED [SI INSERT]: ",
        "REQUEST BILL FAILED [PRINT JOB]: ",
    )

    for marker in diagnostics:
        assert marker in source

    assert "def render_sales_invoice_html(" in source

    assert (
        '"DMT custom_cashier_invoice_print_format is required"'
        in source
    )

    assert "print_format=invoice_print_format" in source
    assert "as_pdf=False" in source

    assert re.search(
        r'job\.render_mode\s*=\s*\(?\s*"HTML"\s*\)?',
        source,
    )
    assert re.search(r"job\.html_content\s*=", source)
    assert re.search(r"job\.pdf_base64\s*=", source)

    assert "def render_sales_invoice_pdf(" not in source
    assert "def encode_pdf_base64(" not in source
    assert "as_pdf=True" not in source
    assert "custom_cashier_print_format" not in source
    assert 'or "Standard"' not in source
