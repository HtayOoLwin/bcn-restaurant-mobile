from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SERVER_SCRIPTS = ROOT / "server_scripts" / "mobile"
DOC = ROOT / "docs" / "server-script-mobile.md"


def _read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def test_ourcity_server_script_mirror_exists():
    for name in (
        "bootstrap.py",
        "tables.py",
        "menu.py",
        "create_order.py",
        "request_for_bill.py",
        "cashier_billing.py",
        "cashier_print_bill.py",
        "print_jobs.py",
        "print_job_result.py",
    ):
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
    assert '"docstatus": ["in", [0, 1]]' in source
    assert 'sales_order.custom_restaurant_status = "Open"' in source
    assert "custom_client_order_id" in source
    assert "custom_kitchen_note" in source
    assert "custom_kitchen_counter" in source
    assert "custom_printed_qty" in source
    assert ".submit(" not in source
    assert "Table is currently in Billing" in source
    assert "Restaurant Table Session" not in source


def test_create_order_applies_and_recalculates_dmt_taxes():
    source = _read(SERVER_SCRIPTS / "create_order.py")
    assert "profile.taxes_and_charges" in source
    assert "sales_order.taxes_and_charges" in source
    assert "erpnext.accounts.services.taxes.get_taxes_and_charges" in source
    assert 'sales_order.append("taxes", tax)' in source
    assert "sales_order.set_taxes()" not in source
    assert "sales_order.calculate_taxes_and_totals()" in source


def test_request_for_bill_submits_sales_order_creates_draft_invoice_and_auto_print_job():
    source = _read(SERVER_SCRIPTS / "request_for_bill.py")
    assert 'sales_order.custom_restaurant_status = "Billing"' in source
    assert "sales_order.submit()" in source
    assert "erpnext.selling.doctype.sales_order.sales_order.make_sales_invoice" in source
    assert "sales_invoice.update_stock = 1" in source
    assert "sales_invoice.insert(ignore_permissions=True)" in source
    assert "sales_invoice.submit()" not in source
    assert '"Sales Invoice"' in source
    assert (
        '"frappe.www.printview.get_html_and_style"'
        in source
    )
    assert "render_sales_invoice_html" in source
    assert 'rendered.get("html")' in source
    assert 'rendered.get("style")' in source
    assert "frappe.get_print(" not in source
    assert "as_pdf=False" not in source
    assert "as_pdf=True" not in source
    assert 'job.render_mode = "HTML"' in source
    assert 'job.html_content = rendered["html_content"]' in source
    assert 'job.pdf_base64 = ""' in source
    assert "encode_pdf_base64" not in source
    assert 'job.status = "Pending"' in source
    assert 'request_id = "bill-request|" + sales_order.name' in source
    assert '"duplicate": True' in source
    assert "frappe.db.commit" not in source
    assert "frappe.db.rollback" not in source


def test_cashier_billing_lists_open_and_submitted_billing_sales_orders():
    source = _read(SERVER_SCRIPTS / "cashier_billing.py")
    assert 'COMPANY = "Doh Myot Daw BBQ & Restaurant"' in source
    assert 'POS_PROFILE = "DMT"' in source
    assert '"docstatus": 0' in source
    assert '"custom_restaurant_status": "Open"' in source
    assert '"docstatus": 1' in source
    assert '"custom_restaurant_status": "Billing"' in source
    assert "get_linked_draft_sales_invoice_names" in source
    assert '"sales_invoice": draft_invoice' in source
    assert '"payment_enabled": bool(draft_invoice)' in source
    assert '"bills"' in source
    assert '"modes"' in source
    assert '"last_print_status"' in source
    assert '"last_print_job"' in source
    assert "Restaurant Table Session" not in source


def test_cashier_manual_print_requires_bill_request_and_reprints_draft_invoice():
    source = _read(SERVER_SCRIPTS / "cashier_print_bill.py")
    assert 'POS_PROFILE = "DMT"' in source
    assert 'request_id = (frappe.form_dict.get("request_id") or "").strip()' in source
    assert "request_id is required" in source
    assert 'frappe.db.exists("BCN Print Job", {"request_id": request_id})' in source
    assert "Waiter must Request for Bill before cashier printing" in source
    assert 'sales_order.docstatus == 1 and restaurant_status == "Billing"' in source
    assert "get_linked_draft_invoice_names" in source
    assert '"Sales Invoice"' in source
    assert (
        '"frappe.www.printview.get_html_and_style"'
        in source
    )
    assert "render_invoice_html" in source
    assert 'rendered.get("html")' in source
    assert 'rendered.get("style")' in source
    assert "frappe.get_print(" not in source
    assert "as_pdf=False" not in source
    assert "as_pdf=True" not in source
    assert 'job.render_mode = "HTML"' in source
    assert 'job.html_content = rendered["html_content"]' in source
    assert 'job.request_id = request_id' in source
    assert 'job.status = "Pending"' in source
    assert "custom_cashier_printer" in source
    assert "pdf_base64" in source
    assert "encode_pdf_base64" not in source
    assert "publish_realtime" not in source


def test_cashier_print_bill_duplicate_request_returns_existing_job():
    source = _read(SERVER_SCRIPTS / "cashier_print_bill.py")
    assert '"duplicate": True' in source
    assert "Print request ID is already used for another document" in source


def test_cashier_print_bill_serializes_request_id_check_before_job_creation():
    source = _read(SERVER_SCRIPTS / "cashier_print_bill.py")
    lock_marker = "SELECT name FROM `tabPOS Profile` WHERE name=%(name)s FOR UPDATE"
    request_check = 'frappe.db.exists("BCN Print Job", {"request_id": request_id})'
    assert lock_marker in source
    assert source.index(lock_marker) < source.index(request_check)


def test_cashier_print_bill_closed_reprint_copies_existing_snapshot():
    source = _read(SERVER_SCRIPTS / "cashier_print_bill.py")
    assert 'restaurant_status == "Closed"' in source
    assert "No printable cashier snapshot exists" in source
    assert 'previous_mode = (previous_job.get("render_mode") or "PDF").strip().upper()' in source
    assert 'if previous_mode == "HTML":' in source
    assert 'previous_job.get("html_content")' in source
    assert 'previous_job.get("pdf_base64")' in source
    assert 'job.render_mode = "PDF"' in source


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
    assert '"render_mode": (job.get("render_mode") or "PDF")' in source
    assert '"html_content": job.get("html_content") or ""' in source
    assert '"pdf_base64": job.pdf_base64' in source


def test_print_job_result_is_owned_and_retry_safe():
    source = _read(SERVER_SCRIPTS / "print_job_result.py")
    assert "BCN Printer Client" in source
    assert "claimed_by" in source
    assert '["Printed", "Failed"]' in source
    assert '"duplicate": True' in source
    assert "FOR UPDATE" in source
    assert "conflict" in source.lower()


def test_cashier_pay_submits_existing_draft_invoice_then_closes_sales_order():
    source = _read(SERVER_SCRIPTS / "cashier_billing.py")
    assert 'action == "Pay"' in source
    assert "FOR UPDATE" in source
    assert 'sales_order.docstatus == 1 and restaurant_status == "Billing"' in source
    assert "get_linked_draft_sales_invoice_names" in source
    assert "sales_invoice.update_stock = 1" in source
    assert "sales_invoice.submit()" in source
    assert "Payment Entry" in source
    assert "Payment Entry Reference" in source
    assert '"custom_restaurant_status",\n            "Closed"' in source
    assert "Please request the bill before taking payment" in source
    assert '"duplicate"' in source
    assert "frappe.db.commit" not in source
    assert "frappe.db.rollback" not in source
    assert "Delivery Note" not in source


def test_cashier_pay_skips_non_positive_tender_rows():
    source = _read(SERVER_SCRIPTS / "cashier_billing.py")
    assert 'if amount <= 0:\n            continue' in source
    assert "Payment amount must be greater than zero" not in source


def test_tables_reports_available_occupied_and_submitted_billing_orders():
    source = _read(SERVER_SCRIPTS / "tables.py")
    assert "Sales Order" in source
    assert "custom_restaurant_status" in source
    assert 'table_status = "Available"' in source
    assert 'table_status = "Occupied"' in source
    assert 'table_status = "Billing"' in source
    assert '"docstatus": ["in", [0, 1]]' in source
    assert 'row.docstatus == 1 and row.custom_restaurant_status == "Billing"' in source
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
        "bcn_request_for_bill",
        "bcn_cashier_billing",
        "bcn_cashier_print_bill",
        "bcn_print_jobs",
        "bcn_print_job_result",
    ):
        assert alias in source
    assert "OurCity" in source
    assert "custom app installation" in source.lower()
    assert "not required" in source.lower()
    assert "render_mode" in source
    assert "html_content" in source
    assert "pdf_base64" in source
    assert "Microsoft Edge" in source
    assert "wkhtmltopdf" in source
    assert "Windows client first" in source



def test_custom_admin_role_is_allowed_across_mobile_server_scripts():
    bootstrap = _read(SERVER_SCRIPTS / "bootstrap.py")
    assert 'or "Admin" in roles' in bootstrap

    for name in (
        "create_order.py",
        "waiter_order_progress.py",
        "request_for_bill.py",
        "cashier_billing.py",
        "cashier_print_bill.py",
    ):
        source = _read(SERVER_SCRIPTS / name)
        assert 'or "Admin" in roles' in source, name



def test_waiter_read_endpoints_are_role_protected():
    for name in ("tables.py", "menu.py"):
        source = _read(SERVER_SCRIPTS / name)

        assert '"Waiter" in roles' in source, name
        assert 'or "Admin" in roles' in source, name
        assert 'or "Cashier" in roles' not in source, name
        assert "allowed_user" in source, name
