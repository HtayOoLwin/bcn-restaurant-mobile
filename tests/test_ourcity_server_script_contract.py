from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SERVER_SCRIPTS = ROOT / "server_scripts" / "mobile"
DOC = ROOT / "docs" / "server-script-mobile.md"


def _read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def test_ourcity_server_script_mirror_exists():
    for name in ("bootstrap.py", "tables.py", "menu.py", "create_order.py"):
        assert (SERVER_SCRIPTS / name).exists(), name
    assert DOC.exists()


def test_create_order_reuses_open_draft_sales_order_and_preserves_print_delta():
    source = _read(SERVER_SCRIPTS / "create_order.py")
    assert 'COMPANY = "Doh Myot Daw BBQ & Restaurant"' in source
    assert 'POS_PROFILE = "DMT"' in source
    assert 'PRICE_LIST = "Standard Selling"' in source
    assert 'CURRENCY = "MMK"' in source
    assert "json.loads" in source
    assert "frappe.parse_json" not in source
    assert '"docstatus": 0' in source
    assert 'sales_order.custom_restaurant_status = "Open"' in source
    assert "custom_client_order_id" in source
    assert "custom_kitchen_note" in source
    assert "custom_kitchen_counter" in source
    assert "custom_printed_qty" in source
    assert ".submit(" not in source
    assert "Restaurant Table Session" not in source


def test_create_order_applies_and_recalculates_dmt_taxes():
    source = _read(SERVER_SCRIPTS / "create_order.py")
    assert "profile.taxes_and_charges" in source
    assert "sales_order.taxes_and_charges" in source
    assert "erpnext.accounts.services.taxes.get_taxes_and_charges" in source
    assert 'sales_order.append("taxes", tax)' in source
    assert "sales_order.set_taxes()" not in source
    assert "sales_order.calculate_taxes_and_totals()" in source


def test_create_order_blocks_new_waiter_orders_while_table_is_billing():
    source = _read(SERVER_SCRIPTS / "create_order.py")
    assert '"custom_restaurant_status": ["in", ["Open", "Billing"]]' in source
    assert "Table is currently in Billing" in source


def test_tables_reports_available_occupied_and_billing_from_draft_sales_orders():
    source = _read(SERVER_SCRIPTS / "tables.py")
    assert "Sales Order" in source
    assert "custom_restaurant_status" in source
    assert 'table_status = "Available"' in source
    assert 'table_status = "Occupied"' in source
    assert 'table_status = "Billing"' in source
    assert '"docstatus": 0' in source
    assert "Restaurant Table Session" not in source


def test_bootstrap_and_menu_match_ourcity_server_script_deployment():
    bootstrap = _read(SERVER_SCRIPTS / "bootstrap.py")
    menu = _read(SERVER_SCRIPTS / "menu.py")
    for source in (bootstrap, menu):
        assert 'COMPANY = "Doh Myot Daw BBQ & Restaurant"' in source
        assert 'PRICE_LIST = "Standard Selling"' in source
        assert 'CURRENCY = "MMK"' in source
    assert 'POS_PROFILE = "DMT"' in menu
    assert '"kitchen"' not in bootstrap
    assert "Restaurant Table Session" not in menu


def test_server_script_doc_describes_aliases_and_no_custom_app_requirement():
    source = _read(DOC)
    for alias in (
        "bcn_mobile_bootstrap",
        "bcn_mobile_tables",
        "bcn_mobile_menu",
        "bcn_mobile_create_order",
        "bcn_cashier_billing",
    ):
        assert alias in source
    assert "OurCity" in source
    assert "custom app installation" in source.lower()
    assert "not required" in source.lower()
