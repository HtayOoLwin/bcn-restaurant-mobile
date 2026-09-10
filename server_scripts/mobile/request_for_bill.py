# Server Script API: bcn_request_for_bill
# Deployment target: https://ourcity.s.frappe.cloud
#
# Waiter flow:
# - lock one Open Draft Sales Order
# - submit Sales Order
# - create exactly one Draft Sales Invoice
# - queue an HTML snapshot of that Draft Sales Invoice to the existing BCN Print Job
# - keep the table in Billing until cashier payment closes it
#
# The request is retry-safe and does not commit manually.

COMPANY = "Doh Myot Daw BBQ & Restaurant"
POS_PROFILE = "DMT"
CURRENCY = "MMK"
AMOUNT_TOLERANCE = 0.01


def get_linked_draft_invoice_names(sales_order_name):
    rows = frappe.get_all(
        "Sales Invoice Item",
        filters={"sales_order": sales_order_name, "docstatus": 0},
        fields=["parent"],
        order_by="creation asc",
        limit_page_length=50,
    )
    names = []
    for row in rows:
        if row.parent and row.parent not in names:
            invoice_status = frappe.db.get_value("Sales Invoice", row.parent, "docstatus")
            if invoice_status == 0:
                names.append(row.parent)
    return names


def validate_invoice_totals(sales_invoice, frozen_net, frozen_taxes, frozen_grand):
    if abs(float(sales_invoice.net_total or 0) - frozen_net) > AMOUNT_TOLERANCE:
        frappe.throw("Sales Invoice net total does not match the Sales Order")
    if abs(float(sales_invoice.total_taxes_and_charges or 0) - frozen_taxes) > AMOUNT_TOLERANCE:
        frappe.throw("Sales Invoice taxes do not match the Sales Order")
    if abs(float(sales_invoice.grand_total or 0) - frozen_grand) > AMOUNT_TOLERANCE:
        frappe.throw("Sales Invoice grand total does not match the Sales Order")


def render_sales_invoice_html(profile, sales_invoice):
    invoice_print_format = (
        profile.get("custom_cashier_invoice_print_format") or ""
    ).strip()

    if not invoice_print_format:
        frappe.throw("DMT custom_cashier_invoice_print_format is required")

    print_format_row = frappe.db.get_value(
        "Print Format",
        invoice_print_format,
        ["name", "doc_type", "disabled"],
        as_dict=True,
    )
    if not print_format_row:
        frappe.throw(
            "Cashier Sales Invoice print format not found: "
            + invoice_print_format
        )
    if print_format_row.disabled:
        frappe.throw(
            "Cashier Sales Invoice print format is disabled: "
            + invoice_print_format
        )
    if print_format_row.doc_type != "Sales Invoice":
        frappe.throw(
            "Cashier Sales Invoice print format must be for Sales Invoice"
        )

    html_content = frappe.get_print(
        "Sales Invoice",
        sales_invoice.name,
        print_format=invoice_print_format,
        as_pdf=False,
    )
    if not str(html_content or "").strip():
        frappe.throw("Cashier HTML snapshot is empty")
    return {
        "html_content": html_content,
        "print_format": invoice_print_format,
    }


def ensure_print_job(sales_order, sales_invoice, profile, current_user):
    if not frappe.db.exists("DocType", "BCN Print Job"):
        frappe.throw("BCN Print Job is not configured")

    request_id = "bill-request|" + sales_order.name
    existing_job_name = frappe.db.exists("BCN Print Job", {"request_id": request_id})
    if existing_job_name:
        existing_job = frappe.get_doc("BCN Print Job", existing_job_name)
        if existing_job.document_type != "Sales Order" or existing_job.document_name != sales_order.name:
            frappe.throw("Bill request print ID is already used by another document")
        return existing_job

    printer_name = (profile.get("custom_cashier_printer") or "").strip()
    if not printer_name:
        frappe.throw("DMT custom_cashier_printer is required")

    rendered = render_sales_invoice_html(profile, sales_invoice)

    job = frappe.new_doc("BCN Print Job")
    job.request_id = request_id
    job.document_type = "Sales Order"
    job.document_name = sales_order.name
    job.printer_name = printer_name
    job.print_format = rendered["print_format"]
    job.render_mode = "HTML"
    job.html_content = rendered["html_content"]
    job.pdf_base64 = ""
    job.status = "Pending"
    job.attempt_count = 0
    job.requested_by = current_user
    job.requested_at = frappe.utils.now()
    job.insert(ignore_permissions=True)
    return job


current_user = frappe.session.user
if not current_user or current_user == "Guest":
    frappe.throw("Authentication is required.")

role_rows = frappe.get_all(
    "Has Role",
    filters={"parent": current_user, "parenttype": "User"},
    fields=["role"],
    limit_page_length=200,
)
roles = []
for role_row in role_rows:
    if role_row.role and role_row.role not in roles:
        roles.append(role_row.role)

allowed_user = current_user == "Administrator" or "System Manager" in roles or "Waiter" in roles or "Restaurant Manager" in roles
if not allowed_user:
    frappe.throw("You are not allowed to request restaurant bills.")

sales_order_name = (frappe.form_dict.get("sales_order") or "").strip()
if not sales_order_name:
    frappe.throw("sales_order is required")

locked_rows = frappe.db.sql(
    "SELECT name FROM `tabSales Order` WHERE name=%(name)s FOR UPDATE",
    {"name": sales_order_name},
    as_dict=True,
)
if not locked_rows:
    frappe.throw("Sales Order not found: " + sales_order_name)

sales_order = frappe.get_doc("Sales Order", sales_order_name)
if sales_order.company != COMPANY:
    frappe.throw("Sales Order does not belong to the restaurant company")
if sales_order.currency != CURRENCY:
    frappe.throw("Restaurant billing requires MMK Sales Order currency")

restaurant_status = (sales_order.get("custom_restaurant_status") or "").strip()
profile = frappe.get_doc("POS Profile", POS_PROFILE)

if sales_order.docstatus == 1 and restaurant_status == "Billing":
    draft_invoices = get_linked_draft_invoice_names(sales_order.name)
    if not draft_invoices:
        frappe.throw("Bill Requested Sales Order has no Draft Sales Invoice")
    if len(draft_invoices) > 1:
        frappe.throw("Sales Order has multiple Draft Sales Invoices")
    sales_invoice = frappe.get_doc("Sales Invoice", draft_invoices[0])
    print_job = ensure_print_job(sales_order, sales_invoice, profile, current_user)
    frappe.response["message"] = {
        "sales_order": sales_order.name,
        "sales_invoice": sales_invoice.name,
        "print_job": print_job.name,
        "print_status": print_job.status,
        "restaurant_status": "Billing",
        "duplicate": True,
    }

elif sales_order.docstatus == 0 and restaurant_status == "Open":
    active_orders = frappe.get_all(
        "Sales Order",
        filters={
            "company": COMPANY,
            "customer": sales_order.customer,
            "docstatus": ["in", [0, 1]],
            "custom_restaurant_status": ["in", ["Open", "Billing"]],
        },
        fields=["name", "docstatus", "custom_restaurant_status"],
        order_by="creation asc",
        limit_page_length=5,
    )
    valid_active_names = []
    for row in active_orders:
        if (row.docstatus == 0 and row.custom_restaurant_status == "Open") or (row.docstatus == 1 and row.custom_restaurant_status == "Billing"):
            valid_active_names.append(row.name)
    if len(valid_active_names) != 1 or valid_active_names[0] != sales_order.name:
        frappe.throw("Restaurant table does not have one unique active Sales Order")
    if not sales_order.items:
        frappe.throw("Sales Order has no items")

    sales_order.calculate_taxes_and_totals()
    frozen_net = float(sales_order.net_total or 0)
    frozen_taxes = float(sales_order.total_taxes_and_charges or 0)
    frozen_grand = float(sales_order.grand_total or 0)

    sales_order.custom_restaurant_status = "Billing"
    sales_order.flags.ignore_permissions = True
    sales_order.submit()

    sales_invoice = frappe.call(
        "erpnext.selling.doctype.sales_order.sales_order.make_sales_invoice",
        source_name=sales_order.name,
        ignore_permissions=True,
    )
    sales_invoice.flags.ignore_permissions = True
    sales_invoice.update_stock = 1
    sales_invoice.calculate_taxes_and_totals()
    validate_invoice_totals(sales_invoice, frozen_net, frozen_taxes, frozen_grand)
    sales_invoice.insert(ignore_permissions=True)

    print_job = ensure_print_job(sales_order, sales_invoice, profile, current_user)
    frappe.response["message"] = {
        "sales_order": sales_order.name,
        "sales_invoice": sales_invoice.name,
        "print_job": print_job.name,
        "print_status": print_job.status,
        "restaurant_status": "Billing",
        "duplicate": False,
    }

elif sales_order.docstatus == 1 and restaurant_status == "Closed":
    frappe.throw("This order has already been paid.")
else:
    frappe.throw("Sales Order is not in an Open restaurant state")
