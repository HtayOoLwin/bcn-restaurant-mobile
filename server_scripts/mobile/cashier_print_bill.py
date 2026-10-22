# Server Script API: bcn_cashier_print_bill
# OurCity V2 - cashier reprint of the latest Request for Bill snapshot.
# Works with bcn_request_for_bill V2: bill-request|<SO>|<revision>
# This API never changes the SO, creates an SI, or recalculates room charges.
# Required: Sales Order.custom_bill_revision and BCN Print Job.
# Cashier can reprint Draft Billing, Payment Pending, or Closed bills.
#
# IMPORTANT: Install only with the V2 Create Order, Request Bill and Cashier APIs.

COMPANY = "Doh Myot Daw BBQ & Restaurant"

current_user = frappe.session.user
if not current_user or current_user == "Guest":
    frappe.throw("Authentication is required")

role_rows = frappe.get_all("Has Role", filters={"parent": current_user, "parenttype": "User"}, fields=["role"], limit_page_length=200)
roles = [row.role for row in role_rows]
if not (current_user == "Administrator" or "Admin" in roles or "System Manager" in roles or "Restaurant Manager" in roles or "Cashier" in roles):
    frappe.throw("You are not allowed to print cashier bills")

sales_order_name = (frappe.form_dict.get("sales_order") or "").strip()
request_id = (frappe.form_dict.get("request_id") or "").strip()
if not sales_order_name:
    frappe.throw("sales_order is required")
if not request_id:
    frappe.throw("request_id is required")
if len(request_id) > 140:
    frappe.throw("request_id is too long")
if request_id.startswith("bill-request|"):
    frappe.throw("Reserved request_id prefix. Use a unique cashier-print ID")
if not frappe.db.exists("DocType", "BCN Print Job"):
    frappe.throw("BCN Print Job is not configured")

# Lock order BEFORE finding the source bill and existing job.
locked_rows = frappe.db.sql(
    "SELECT name FROM `tabSales Order` WHERE name=%(name)s FOR UPDATE",
    {"name": sales_order_name},
    as_dict=True,
)
if not locked_rows:
    frappe.throw("Sales Order not found: " + sales_order_name)

sales_order = frappe.get_doc("Sales Order", sales_order_name)
if sales_order.company != COMPANY:
    frappe.throw("Sales Order does not belong to restaurant company")

restaurant_status = (sales_order.get("custom_restaurant_status") or "").strip()
allowed_draft = sales_order.docstatus == 0 and restaurant_status == "Billing"
allowed_pending = sales_order.docstatus == 1 and restaurant_status == "Payment Pending"
allowed_closed = sales_order.docstatus == 1 and restaurant_status == "Closed"
if not (allowed_draft or allowed_pending or allowed_closed):
    frappe.throw("Request for Bill first. Order is not in a printable state")

revision = int(sales_order.get("custom_bill_revision") or 0)
if revision < 1:
    frappe.throw("Latest Request for Bill revision is missing")

# Every reprint uses the latest immutable auto-print snapshot, never a stale
# earlier revision and never a newly rendered, mutable SO document.
source_id = "bill-request|" + sales_order.name + "|" + str(revision)
source_name = frappe.db.exists("BCN Print Job", {"request_id": source_id})
if not source_name:
    frappe.throw("Latest bill snapshot is missing: " + source_id)
source_job = frappe.get_doc("BCN Print Job", source_name)
if source_job.document_type != "Sales Order" or source_job.document_name != sales_order.name:
    frappe.throw("Latest bill snapshot points to the wrong order")

mode = (source_job.get("render_mode") or "").strip().upper()
if mode == "HTML":
    if not (source_job.get("html_content") or "").strip():
        frappe.throw("Latest bill HTML snapshot is empty")
elif mode == "PDF":
    if not (source_job.get("pdf_base64") or "").strip():
        frappe.throw("Latest bill PDF snapshot is empty")
else:
    frappe.throw("Unsupported latest bill snapshot render mode")

existing_name = frappe.db.exists("BCN Print Job", {"request_id": request_id})
if existing_name:
    job = frappe.get_doc("BCN Print Job", existing_name)
    if job.document_type != "Sales Order" or job.document_name != sales_order.name:
        frappe.throw("Print request ID is already used for another document")
    # If an old request ID gets retried after bill revision changes, reject it:
    # otherwise a previous stale print job could be mistaken for a current bill.
    original_id = (job.get("request_id") or "")
    if not original_id:
        frappe.throw("Existing print job request ID is invalid")
    if job.print_format != source_job.print_format or job.render_mode != source_job.render_mode:
        frappe.throw("Print request refers to a different bill snapshot")
    if mode == "HTML" and job.get("html_content") != source_job.get("html_content"):
        frappe.throw("Print request refers to an outdated bill revision")
    if mode == "PDF" and job.get("pdf_base64") != source_job.get("pdf_base64"):
        frappe.throw("Print request refers to an outdated bill revision")
    frappe.response["message"] = {
        "sales_order": sales_order.name,
        "request_id": request_id,
        "print_job": job.name,
        "status": job.status,
        "bill_revision": revision,
        "restaurant_status": restaurant_status,
        "is_reprint": True,
        "duplicate": True,
    }
else:
    job = frappe.new_doc("BCN Print Job")
    job.request_id = request_id
    job.document_type = "Sales Order"
    job.document_name = sales_order.name
    job.printer_name = source_job.printer_name
    job.print_format = source_job.print_format
    job.render_mode = mode
    job.html_content = source_job.get("html_content") or ""
    job.pdf_base64 = source_job.get("pdf_base64") or ""
    job.status = "Pending"
    job.attempt_count = 0
    job.requested_by = current_user
    job.requested_at = frappe.utils.now()
    job.insert(ignore_permissions=True)
    frappe.response["message"] = {
        "sales_order": sales_order.name,
        "request_id": request_id,
        "print_job": job.name,
        "status": job.status,
        "bill_revision": revision,
        "restaurant_status": restaurant_status,
        "is_reprint": True,
        "duplicate": False,
    }
