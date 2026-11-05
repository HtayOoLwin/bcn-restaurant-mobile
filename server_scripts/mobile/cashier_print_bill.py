# Server Script API: bcn_cashier_print_bill
# Prints the final submitted Sales Invoice after cashier checkout.
POS_PROFILE = "DMT"
profile = frappe.get_doc("POS Profile", POS_PROFILE)
COMPANY = (profile.company or "").strip()
if not COMPANY:
    frappe.throw("POS Profile DMT must have a Company")

user = frappe.session.user
if not user or user == "Guest":
    frappe.throw("Authentication required")

roles = frappe.get_all("Has Role", filters={"parent": user, "parenttype": "User"}, fields=["role"], limit_page_length=100)
role_names = [row.role for row in roles]
if not (user == "Administrator" or "System Manager" in role_names or "Cashier" in role_names or "Restaurant Manager" in role_names):
    frappe.throw("Not allowed to print cashier receipts")

sales_order = (frappe.form_dict.get("sales_order") or "").strip()
request_id = (frappe.form_dict.get("request_id") or "").strip()
print_source = (frappe.form_dict.get("print_source") or "cashier").strip()
if not sales_order or not request_id:
    frappe.throw("sales_order and request_id are required")
if len(request_id) > 140 or request_id.startswith("bill-request|"):
    frappe.throw("Invalid request_id")
if print_source not in ("cashier", "daily_report"):
    frappe.throw("Invalid print_source")

locked = frappe.db.sql(
    "SELECT name FROM `tabSales Order` WHERE name=%(name)s FOR UPDATE",
    {"name": sales_order}, as_dict=True
)
if not locked:
    frappe.throw("Sales Order not found")
order = frappe.get_doc("Sales Order", sales_order)
if order.company != COMPANY:
    frappe.throw(
        "Sales Order Company (" + str(order.company)
        + ") does not match POS Profile DMT Company (" + COMPANY + ")"
    )
if order.docstatus != 1 or order.custom_restaurant_status != "Closed":
    frappe.throw(
        "Only completed checkout receipts may be printed. "
        + "Sales Order docstatus=" + str(order.docstatus)
        + ", restaurant_status=" + str(order.custom_restaurant_status or "")
    )

invoice_rows = frappe.get_all(
    "Sales Invoice Item", filters={"sales_order": sales_order, "docstatus": 1},
    fields=["parent"], limit_page_length=200
)
invoice_names = []
for row in invoice_rows:
    if row.parent not in invoice_names:
        invoice_names.append(row.parent)
if len(invoice_names) != 1:
    frappe.throw("Expected exactly one submitted Sales Invoice")
invoice = frappe.get_doc("Sales Invoice", invoice_names[0])
if invoice.docstatus != 1 or invoice.company != COMPANY:
    frappe.throw("Submitted Sales Invoice is invalid")

printer = (profile.get("custom_cashier_printer") or "").strip()
if not printer:
    frappe.throw("POS Profile DMT cashier printer is not configured")
fmt = (profile.get("custom_cashier_invoice_print_format") or "").strip()
if not fmt:
    fmt = "Standard"
if fmt != "Standard":
    row = frappe.db.get_value("Print Format", fmt, ["doc_type", "disabled"], as_dict=True)
    if not row or row.doc_type != "Sales Invoice" or row.disabled:
        frappe.throw("Cashier receipt print format must be for Sales Invoice")

if not frappe.db.exists("DocType", "BCN Print Job"):
    frappe.throw("BCN Print Job is missing")

existing = frappe.db.exists("BCN Print Job", {"request_id": request_id})
if existing:
    job = frappe.get_doc("BCN Print Job", existing)
    if job.document_type != "Sales Invoice" or job.document_name != invoice.name:
        frappe.throw("Print request ID belongs to another document")
    frappe.response["message"] = {
        "sales_order": sales_order, "sales_invoice": invoice.name,
        "print_job": job.name, "request_id": request_id,
        "status": job.status, "duplicate": True, "success": True,
        "print_source": print_source,
    }
else:
    rendered = frappe.call(
        "frappe.www.printview.get_html_and_style",
        doc="Sales Invoice", name=invoice.name,
        print_format=fmt, no_letterhead=0,
    )
    if not (rendered.get("html") or "").strip():
        frappe.throw("Receipt HTML is empty")
    receipt_body = rendered.get("html") or ""
    if print_source == "daily_report":
        # Add a visible marker to the queued HTML only.
        # Do not modify the submitted invoice or its Print Format.
        reprint_banner = (
            "<div style='text-align:center;font-weight:800;font-size:20px;"
            "padding:8px 0;margin:6px 0 10px;"
            "border-top:1px dashed #000;border-bottom:1px dashed #000;'>"
            "REPRINT</div>"
        )
        receipt_body = reprint_banner + receipt_body
    html = "<!doctype html><html><head><meta charset='utf-8'><style>" + (
        rendered.get("style") or ""
    ) + "</style></head><body>" + receipt_body + "</body></html>"
    job = frappe.new_doc("BCN Print Job")
    job.request_id = request_id
    job.document_type = "Sales Invoice"
    job.document_name = invoice.name
    job.printer_name = printer
    job.print_format = fmt
    job.render_mode = "HTML"
    job.html_content = html
    job.pdf_base64 = ""
    job.status = "Pending"
    job.attempt_count = 0
    job.requested_by = user
    job.requested_at = frappe.utils.now()
    job.insert(ignore_permissions=True)
    frappe.response["message"] = {
        "sales_order": sales_order, "sales_invoice": invoice.name,
        "print_job": job.name, "request_id": request_id,
        "status": job.status, "duplicate": False, "success": True,
        "print_source": print_source,
    }
