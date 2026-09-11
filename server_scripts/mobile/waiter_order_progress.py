# Server Script API: bcn_waiter_order_progress
# Deployment target: https://ourcity.s.frappe.cloud
#
# Current Server-Script-only restaurant flow:
# - waiter orders are Open Draft Sales Orders
# - Request for Bill moves the order out of this Open list into Billing
# - this endpoint reads the same active-order state used by the table screen

COMPANY = "Doh Myot Daw BBQ & Restaurant"

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
    or "Admin" in roles
    or "System Manager" in roles
    or "Waiter" in roles
    or "Restaurant Manager" in roles
)

if not allowed_user:
    frappe.throw("You are not allowed to view restaurant order progress.")

orders = frappe.get_all(
    "Sales Order",
    filters={
        "company": COMPANY,
        "docstatus": 0,
        "custom_restaurant_status": "Open",
    },
    fields=[
        "name",
        "customer",
        "customer_name",
        "creation",
        "grand_total",
    ],
    order_by="creation asc",
    limit_page_length=500,
)

result = []
for order in orders:
    item_rows = frappe.get_all(
        "Sales Order Item",
        filters={
            "parent": order.name,
            "parenttype": "Sales Order",
            "docstatus": 0,
        },
        fields=[
            "name",
            "idx",
            "item_code",
            "item_name",
            "qty",
            "uom",
            "custom_kitchen_counter",
            "custom_kitchen_note",
        ],
        order_by="idx asc",
        limit_page_length=1000,
    )

    details = []
    total_qty = 0.0
    for row in item_rows:
        qty = frappe.utils.flt(row.qty)
        total_qty = total_qty + qty
        details.append(
            {
                "row_name": row.name,
                "item_code": row.item_code,
                "item_name": row.item_name or row.item_code,
                "qty": float(qty),
                "uom": row.uom,
                "kitchen_counter": row.custom_kitchen_counter,
                "kitchen_note": row.custom_kitchen_note,
                "status": "New",
                "can_cancel": False,
            }
        )

    result.append(
        {
            "name": order.name,
            "customer": order.customer,
            "customer_name": order.customer_name or order.customer,
            "creation": order.creation,
            "grand_total": float(order.grand_total or 0),
            "total_qty": float(total_qty),
            "active_qty": float(total_qty),
            "new_qty": float(total_qty),
            "preparing_qty": 0.0,
            "ready_qty": 0.0,
            "served_qty": 0.0,
            "cancelled_qty": 0.0,
            "fully_served": False,
            "preparation_summary": "New",
            "items": details,
        }
    )

frappe.response["message"] = {
    "orders": result,
    "count": len(result),
    "user": current_user,
}
