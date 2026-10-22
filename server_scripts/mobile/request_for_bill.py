# Server Script API: bcn_request_for_bill
# OurCity V2 staged change: Draft Sales Order bill preview (NO SI at this stage).
# REQUIRED: SO custom_check_in, custom_check_out, custom_duration,
# custom_billable_hours, custom_bill_revision; Item.custom_is_room_charge;
# POS Profile.custom_cashier_order_print_format (Sales Order print format).
# Deploy TOGETHER with cashier and Flutter migration, not alone.

COMPANY = "Doh Myot Daw BBQ & Restaurant"
POS_PROFILE = "DMT"
CURRENCY = "MMK"

user = frappe.session.user
if not user or user == "Guest":
    frappe.throw("Authentication is required.")

roles = [row.role for row in frappe.get_all(\"Has Role\", filters={\"parent\": user, \"parenttype\": \"User\"}, fields=[\"role\"], limit_page_length=200)]
if not (
    user == "Administrator"
    or any(role in roles for role in ["Admin", "System Manager", "Waiter", "Restaurant Manager"])
):
    frappe.throw("You are not allowed to request a bill.")

so_name = (frappe.form_dict.get("sales_order") or "").strip()
if not so_name:
    frappe.throw("sales_order is required")

locked = frappe.db.sql(
    "SELECT name FROM `tabSales Order` WHERE name = %(name)s FOR UPDATE",
    {"name": so_name},
    as_dict=True,
)
if not locked:
    frappe.throw("Sales Order not found")

so = frappe.get_doc("Sales Order", so_name)
if so.company != COMPANY or so.currency != CURRENCY:
    frappe.throw("Restaurant company/currency mismatch")
if so.docstatus != 0 or (so.get("custom_restaurant_status") or "") not in ["Open", "Billing"]:
    frappe.throw("Only an Open or Billing Draft Sales Order can request a bill")
if not so.items:
    frappe.throw("Sales Order has no items")

# A single active SO per customer; another draft or submitted Billing SO is forbidden.
active = frappe.get_all(
    "Sales Order",
    filters={
        "company": COMPANY,
        "customer": so.customer,
        "docstatus": ["in", [0, 1]],
        "custom_restaurant_status": ["in", ["Open", "Billing", "Payment Pending"]],
    },
    fields=["name"],
    limit_page_length=10,
)
if len(active) != 1 or active[0].name != so.name:
    frappe.throw("Table must have exactly one active Sales Order")

now = frappe.utils.now_datetime()
check_in = so.get("custom_check_in") or so.creation
if not check_in:
    frappe.throw("Missing Sales Order check-in time")
check_in = frappe.utils.get_datetime(check_in)
elapsed = (now - check_in).total_seconds()
if elapsed < 0:
    frappe.throw("Check-out cannot be earlier than check-in")
# Whole first hour then any started half-hour rounds up.
# Integer ceiling without importing math (Server Script safe_exec).
half_hours = max(2, int((elapsed + 1799.999999) // 1800))
billable = half_hours / 2.0

room_rows = []
for row in so.items:
    if frappe.db.get_value("Item", row.item_code, "custom_is_room_charge"):
        room_rows.append(row)
if len(room_rows) > 1:
    frappe.throw("Only one Room Charges row per Sales Order is allowed")

if room_rows:
    room = room_rows[0]
    if room.uom != "Hour":
        frappe.throw("Room Charges Item UOM must be Hour")
    item = frappe.get_doc("Item", room.item_code)
    if item.is_stock_item:
        frappe.throw("Room Charges Item must be non-stock")
    # Keep rate frozen on SO item; changing qty triggers amount recalculation.
    room.qty = billable

so.custom_check_in = check_in
so.custom_check_out = now
so.custom_duration = elapsed / 3600.0
so.custom_billable_hours = billable if room_rows else 0
revision = int(so.get("custom_bill_revision") or 0) + 1
so.custom_bill_revision = revision
so.custom_restaurant_status = "Billing"
so.calculate_taxes_and_totals()
so.flags.ignore_permissions = True
so.save(ignore_permissions=True)

# Render a Sales Order draft preview; the former SI print format is invalid here.
profile = frappe.get_doc("POS Profile", POS_PROFILE)
fmt = (profile.get("custom_cashier_order_print_format") or "").strip()
if not fmt:
    frappe.throw("Configure DMT custom_cashier_order_print_format for Sales Order")
format_row = frappe.db.get_value(
    "Print Format", fmt, ["doc_type", "disabled"], as_dict=True
)
if not format_row or format_row.doc_type != "Sales Order" or format_row.disabled:
    frappe.throw("Cashier order print format must be an enabled Sales Order Print Format")

printer = (profile.get("custom_cashier_printer") or "").strip()
if not printer:
    frappe.throw("DMT custom_cashier_printer is required")

if not frappe.db.exists("DocType", "BCN Print Job"):
    frappe.throw("BCN Print Job is not configured")

print_result = frappe.call(
    "frappe.www.printview.get_html_and_style",
    doc="Sales Order",
    name=so.name,
    print_format=fmt,
    no_letterhead=0,
)
html = "<!doctype html><html><head><meta charset='utf-8'><style>" + (
    print_result.get("style") or ""
) + "</style></head><body>" + (print_result.get("html") or "") + "</body></html>"
if not (print_result.get("html") or "").strip():
    frappe.throw("Bill print HTML is empty")

request_id = "bill-request|" + so.name + "|" + str(revision)
if frappe.db.exists("BCN Print Job", {"request_id": request_id}):
    frappe.throw("Duplicate bill print revision")

job = frappe.new_doc("BCN Print Job")
job.request_id = request_id
job.document_type = "Sales Order"
job.document_name = so.name
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
    "sales_order": so.name,
    "sales_invoice": None,
    "restaurant_status": "Billing",
    "docstatus": 0,
    "check_in": str(check_in),
    "check_out": str(now),
    "duration_hours": so.custom_duration,
    "billable_hours": so.custom_billable_hours,
    "room_charges": float(room_rows[0].amount) if room_rows else 0,
    "grand_total": float(so.grand_total or 0),
    "bill_revision": revision,
    "print_job": job.name,
    "print_status": job.status,
    "duplicate": False,
}
