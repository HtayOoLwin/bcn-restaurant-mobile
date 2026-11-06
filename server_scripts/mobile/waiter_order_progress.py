# Server Script API: bcn_waiter_order_progress
# Deployment target: https://ourcity.s.frappe.cloud
#
# Current Server-Script-only restaurant flow:
# - waiter orders are Open Draft Sales Orders
# - Draft Billing orders stay visible so waiter can re-request an updated bill
# - this endpoint reads the same active-order state used by the table screen

COMPANY = "Doh Myot Taw BBQ & Restaurant"

profile = frappe.get_doc("POS Profile", "DMT")
COMPANY = (profile.company or "").strip()
if not COMPANY:
    frappe.throw("POS Profile DMT must have a Company.")

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
        "custom_restaurant_status": ["in", ["Open", "Billing"]],
    },
    fields=[
        "name",
        "customer",
        "customer_name",
        "creation",
        "grand_total",
        "net_total",
        "total_taxes_and_charges",
        "currency",
        "custom_restaurant_status",
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
            "rate",
            "amount",
            "custom_kitchen_counter",
            "custom_kitchen_note",
            "custom_foc",
            "custom_parcel",
            "custom_printed_qty",
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
                "rate": float(row.rate or 0),
                "amount": float(row.amount or 0),
                "kitchen_counter": row.custom_kitchen_counter,
                "kitchen_note": row.custom_kitchen_note,
                "custom_foc": int(row.custom_foc or 0),
                "custom_parcel": int(row.custom_parcel or 0),
                "status": "New",
                "printed_qty": float(row.custom_printed_qty or 0),
                "cancelable_qty": float(
                    max(
                        0,
                        min(
                            qty - frappe.utils.flt(row.custom_printed_qty),
                            qty if len(item_rows) > 1 else qty - 1,
                        ),
                    )
                ),
                "can_cancel": (
                    order.custom_restaurant_status == "Open"
                    and qty - frappe.utils.flt(row.custom_printed_qty) >= 1
                    and (len(item_rows) > 1 or qty >= 2)
                ),
            }
        )

    tax_data = frappe.get_all(
        "Sales Taxes and Charges",
        filters={"parent": order.name, "parenttype": "Sales Order"},
        fields=["account_head", "description", "tax_amount"],
        limit_page_length=100,
    )
    tax_details = []
    for tax in tax_data:
        amount = float(tax.tax_amount or 0)
        if abs(amount) <= 0.00001:
            continue
        account = (tax.account_head or "").lower()
        desc = (tax.description or "").lower()
        if "service charg" in account or "service charg" in desc:
            label = "Service Charges"
        elif "commercial tax" in account or "vat" in account or "commercial tax" in desc:
            label = "Commercial Tax"
        else:
            label = tax.description or tax.account_head or "Tax"
        tax_details.append({"label": label, "amount": amount})

    result.append(
        {
            "name": order.name,
            "customer": order.customer,
            "customer_name": order.customer_name or order.customer,
            "creation": order.creation,
            "grand_total": float(order.grand_total or 0),
            "net_total": float(order.net_total or 0),
            "total_taxes_and_charges": float(order.total_taxes_and_charges or 0),
            "currency": order.currency or "MMK",
            "taxes": tax_details,
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
