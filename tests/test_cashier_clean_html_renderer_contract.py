from pathlib import Path

import pytest
import re


ROOT = Path(__file__).resolve().parents[1]
SERVER = ROOT / "server_scripts" / "mobile"


@pytest.mark.parametrize(
    "script_name",
    [
        "request_for_bill.py",
        "cashier_print_bill.py",
    ],
)
def test_cashier_snapshot_uses_clean_print_renderer(script_name):
    source = (
        SERVER / script_name
    ).read_text(encoding="utf-8")

    assert (
        '"frappe.www.printview.get_html_and_style"'
        in source
    )

    assert "frappe.get_print(" not in source
    assert "as_pdf=False" not in source

    assert 'rendered.get("html")' in source
    assert 'rendered.get("style")' in source

    assert '<meta charset="utf-8">' in source
    assert "<style>" in source
    assert "</style>" in source


@pytest.mark.parametrize(
    "script_name",
    [
        "request_for_bill.py",
        "cashier_print_bill.py",
    ],
)
def test_cashier_snapshot_rejects_empty_rendered_body(script_name):
    source = (
        SERVER / script_name
    ).read_text(encoding="utf-8")

    assert re.search(
        r'if\s+not\s+str\(\s*rendered_html\s+or\s+""\s*\)'
        r'\.strip\(\)\s*:',
        source,
    )

    assert (
        "Cashier rendered HTML body is empty"
        in source
    )
