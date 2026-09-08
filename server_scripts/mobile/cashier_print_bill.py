# Server Script API: bcn_cashier_print_bill
# Deployment target: https://ourcity.s.frappe.cloud
#
# Cashier manual reprint:
# - waiter Request for Bill creates the first automatic print job
# - Open Draft Sales Orders cannot be printed or paid by cashier
# - submitted Billing Sales Orders reprint their linked Draft Sales Invoice
# - Closed orders reprint the latest stored snapshot
# - client request_id keeps retries idempotent

COMPANY = "Doh Myot Daw BBQ & Restaurant"
POS_PROFILE = "DMT"


def encode_pdf_base64(pdf):
    alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    out = []
    i = 0
    length = len(pdf)

    while i < length:
        b0 = pdf[i]
        has_b1 = i + 1 < length
        has_b2 = i + 2 < length
        b1 = pdf[i + 1] if has_b1 else 0
        b2 = pdf[i + 2] if has_b2 else 0
        triple = (b0 << 16) | (b1 << 8) | b2

        out.append(alphabet[(triple >> 18) & 63])
        out.append(alphabet[(triple >> 12) & 63])
        out.append(alphabet[(triple >> 6) & 63] if has_b1 else "=")
        out.append(alphabet[triple & 63] if has_b2 else "=")
        i += 3

    return "".join(out)


def get_linked_draft_invoice_names(sales_order_name):
    rows = frappe.get_all(
        "Sales Invoice Item",
        filters={
            "sales_order": sales_order_name,
            "docstatus": 0,
        },
        fields=["parent"],
        order_by="creation asc",
        limit_page_length=50,
    )

    names = []
    for row in rows:
        if row.parent and row.parent not in names:
            invoice_status = frappe.db.get_value(
                "Sales Invoice",
                row.parent,
                "docstatus",
            )
            if invoice_status == 0:
                names.append(row.parent)
    return names


def render_invoice_pdf(profile, sales_invoice):
    invoice_print_format = (
        profile.get("custom_cashier_invoice_print_format") or ""
    ).strip()

    if invoice_print_format:
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

        pdf = frappe.get_print(
            "Sales Invoice",
            sales_invoice.name,
            print_format=invoice_print_format,
            as_pdf=True,
        )
        return pdf, invoice_print_format

    pdf = frappe.get_print(
        "Sales Invoice",
        sales_invoice.name,
        as_pdf=True,
    )
    metadata_format = (
        profile.get("custom_cashier_print_format") or "Standard"
    ).strip()
    return pdf, metadata_format or "Standard"


current_user = frappe.session.user
if not current_user or current_user == "Guest":
    frappe.throw("Authentication is required.")

role_rows = frappe.get_all(
    "Has Role",
    filters={
        "parent": current_user,
        "parenttype": "User",
    },
    fields=["role"],
    limit_page_length=200,
)

roles = []
for role_row in role_rows:
    if role_row.role and role_row.role not in roles:
        roles.append(role_row.role)

allowed_user = (
    current_user == "Administrator"
    or "System Manager" in roles
    or "Restaurant Manager" in roles
    or "Cashier" in roles
)

if not allowed_user:
    frappe.throw("You are not allowed to print cashier bills.")

sales_order_name = (frappe.form_dict.get("sales_order") or "").strip()
request_id = (frappe.form_dict.get("request_id") or "").strip()

if not sales_order_name:
    frappe.throw("sales_order is required")

if not request_id:
    frappe.throw("request_id is required")

if not frappe.db.exists("DocType", "BCN Print Job"):
    frappe.throw("BCN Print Job is not configured")

serialization_rows = frappe.db.sql(
    "SELECT name FROM `tabPOS Profile` WHERE name=%(name)s FOR UPDATE",
    {"name": POS_PROFILE},
    as_dict=True,
)
if not serialization_rows:
    frappe.throw("POS Profile not found: " + POS_PROFILE)

existing_job_name = frappe.db.exists("BCN Print Job", {"request_id": request_id})
if existing_job_name:
    existing_job = frappe.get_doc("BCN Print Job", existing_job_name)

    if (
        existing_job.document_type != "Sales Order"
        or existing_job.document_name != sales_order_name
    ):
        frappe.throw("Print request ID is already used for another document")

    frappe.response["message"] = {
        "sales_order": sales_order_name,
        "request_id": request_id,
        "print_job": existing_job.name,
        "status": existing_job.status,
        "is_reprint": True,
        "duplicate": True,
    }
else:
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

    restaurant_status = (
        sales_order.get("custom_restaurant_status") or ""
    ).strip()

    if sales_order.docstatus == 0 and restaurant_status == "Open":
        frappe.throw("Waiter must Request for Bill before cashier printing")

    elif sales_order.docstatus == 1 and restaurant_status == "Billing":
        draft_invoices = get_linked_draft_invoice_names(sales_order.name)
        if not draft_invoices:
            frappe.throw("Bill Requested Sales Order has no Draft Sales Invoice")
        if len(draft_invoices) > 1:
            frappe.throw("Sales Order has multiple Draft Sales Invoices")

        sales_invoice = frappe.get_doc("Sales Invoice", draft_invoices[0])
        profile = frappe.get_doc("POS Profile", POS_PROFILE)
        printer_name = (profile.get("custom_cashier_printer") or "").strip()
        if not printer_name:
            frappe.throw("DMT custom_cashier_printer is required")

        pdf, print_format = render_invoice_pdf(profile, sales_invoice)
        pdf_base64 = encode_pdf_base64(pdf)
        if not pdf_base64:
            frappe.throw("Cashier PDF snapshot could not be encoded")

        job = frappe.new_doc("BCN Print Job")
        job.request_id = request_id
        job.document_type = "Sales Order"
        job.document_name = sales_order.name
        job.printer_name = printer_name
        job.print_format = print_format
        job.pdf_base64 = pdf_base64
        job.status = "Pending"
        job.attempt_count = 0
        job.requested_by = current_user
        job.requested_at = frappe.utils.now()
        job.insert(ignore_permissions=True)
        is_reprint = True

    elif sales_order.docstatus == 1 and restaurant_status == "Closed":
        previous_rows = frappe.get_all(
            "BCN Print Job",
            filters={
                "document_type": "Sales Order",
                "document_name": sales_order.name,
            },
            fields=["name"],
            order_by="creation desc",
            limit_page_length=1,
        )

        if not previous_rows:
            frappe.throw("No printable cashier snapshot exists")

        previous_job = frappe.get_doc(
            "BCN Print Job",
            previous_rows[0].name,
        )

        job = frappe.new_doc("BCN Print Job")
        job.request_id = request_id
        job.document_type = "Sales Order"
        job.document_name = sales_order.name
        job.printer_name = previous_job.printer_name
        job.print_format = previous_job.print_format
        job.pdf_base64 = previous_job.pdf_base64
        job.status = "Pending"
        job.attempt_count = 0
        job.requested_by = current_user
        job.requested_at = frappe.utils.now()
        job.insert(ignore_permissions=True)
        is_reprint = True

    else:
        frappe.throw("Sales Order is not in a printable restaurant state")

    frappe.response["message"] = {
        "sales_order": sales_order.name,
        "request_id": request_id,
        "print_job": job.name,
        "status": "Pending",
        "is_reprint": is_reprint,
        "duplicate": False,
    }
