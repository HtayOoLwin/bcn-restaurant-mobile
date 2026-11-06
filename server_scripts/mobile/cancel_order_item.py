# Server Script API: bcn_waiter_cancel_order_item
# OurCity Restaurant - Cancel a chosen quantity from an Open Draft SO item.
# The client supplies item_row_name and cancel_qty (positive whole units).
#
# IMPORTANT:
# - Only Open Draft Sales Orders may be edited.
# - Only units NOT yet printed to kitchen may be cancelled.
# - This does not issue KOT cancellation printouts.
# - The final Sales Order item row cannot be completely removed.

user = frappe.session.user
if not user or user == "Guest":
    frappe.throw("Authentication required")

role_rows = frappe.get_all(
    "Has Role",
    filters={"parent": user, "parenttype": "User"},
    fields=["role"],
    limit_page_length=200,
)
roles = []
for role_row in role_rows:
    if role_row.role and role_row.role not in roles:
        roles.append(role_row.role)

if not (
    user == "Administrator"
    or "Admin" in roles
    or "System Manager" in roles
    or "Waiter" in roles
    or "Restaurant Manager" in roles
):
    frappe.throw("Not allowed to cancel restaurant items")

profile = frappe.get_doc("POS Profile", "DMT")
company = (profile.company or "").strip()
if not company:
    frappe.throw("POS Profile DMT must have a Company")

row_name = (frappe.form_dict.get("item_row_name") or "").strip()
if not row_name:
    frappe.throw("item_row_name is required")

raw_cancel_qty = frappe.form_dict.get("cancel_qty")
cancel_qty = frappe.utils.flt(raw_cancel_qty)
if cancel_qty <= 0 or abs(cancel_qty - round(cancel_qty)) > 0.000001:
    frappe.throw("cancel_qty must be a positive whole number")

# Resolve the SO parent from the requested row.
row_info = frappe.db.get_value(
    "Sales Order Item",
    row_name,
    ["parent", "parenttype"],
    as_dict=True,
)
if not row_info or row_info.parenttype != "Sales Order":
    frappe.throw("Sales Order Item was not found")

# Use the same Customer -> Sales Order lock order as bcn_mobile_create_order.
# This prevents an order append from racing against an item cancellation.
source_customer = frappe.db.get_value(
    "Sales Order", row_info.parent, "customer"
)
if not source_customer:
    frappe.throw("Sales Order table was not found")
locked_customer = frappe.db.sql(
    "SELECT name FROM `tabCustomer` WHERE name = %(name)s FOR UPDATE",
    {"name": source_customer},
    as_dict=True,
)
if not locked_customer:
    frappe.throw("Order table was not found")

# Lock the Sales Order before validating or modifying its child items.
locked = frappe.db.sql(
    "SELECT name FROM `tabSales Order` WHERE name = %(name)s FOR UPDATE",
    {"name": row_info.parent},
    as_dict=True,
)
if not locked:
    frappe.throw("Sales Order was not found")

order = frappe.get_doc("Sales Order", row_info.parent)
if order.company != company:
    frappe.throw("Sales Order company does not match POS Profile DMT")
if order.docstatus != 0 or (order.get("custom_restaurant_status") or "") != "Open":
    frappe.throw("Only Open Draft Sales Orders support item cancellation")

# Block cancelling when a bill preview or checkout is already in progress.
if order.get("custom_check_out"):
    frappe.throw("Bill was already requested. Item cancellation is not allowed")

target = None
for line in order.items:
    if line.name == row_name:
        target = line
        break

if not target:
    frappe.throw("Item no longer exists in this order. Please refresh")

printed_qty = frappe.utils.flt(target.get("custom_printed_qty"))
current_qty = frappe.utils.flt(target.qty)
available_qty = current_qty - printed_qty

if printed_qty < 0 or available_qty < -0.000001:
    frappe.throw("Printed quantity is inconsistent with the order item")

if cancel_qty > available_qty + 0.000001:
    frappe.throw(
        "Cannot cancel more than unprinted quantity ("
        + str(available_qty)
        + "). Refresh order progress"
    )

remaining_qty = current_qty - cancel_qty
remove_row = remaining_qty <= 0.000001
if remove_row and len(order.items) <= 1:
    frappe.throw("Cannot cancel the last item completely. Keep at least one item")

# Avoid cancelling while a kitchen print job is queued or in progress.
# This is a conservative safety check using the existing BCN Print Job.
if frappe.db.exists("DocType", "BCN Print Job"):
    active_print_jobs = frappe.get_all(
        "BCN Print Job",
        filters={
            "document_type": "Sales Order",
            "document_name": order.name,
            "status": ["in", ["Pending", "Processing"]],
        },
        fields=["name"],
        limit_page_length=1,
    )
    if active_print_jobs:
        frappe.throw(
            "A print job is still Pending or Processing for this order. "
            "Please retry after printing completes"
        )

item_name = target.item_name or target.item_code
if remove_row:
    order.remove(target)
else:
    target.qty = remaining_qty

order.calculate_taxes_and_totals()
order.flags.ignore_permissions = True
order.save(ignore_permissions=True)

frappe.response["message"] = {
    "success": True,
    "sales_order": order.name,
    "cancelled_row": row_name,
    "cancelled_item": item_name,
    "cancelled_qty": float(cancel_qty),
    "remaining_qty": float(max(remaining_qty, 0)),
    "grand_total": float(order.grand_total or 0),
    "message": "Item cancelled successfully",
}
