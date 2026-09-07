# Server Script API: bcn_cashier_billing
# Deployment target: https://ourcity.s.frappe.cloud
#
# GET behavior only in this task:
# - list active Draft Sales Orders in Open/Billing state
# - include latest cashier print queue status when BCN Print Job exists
# - include DMT payment modes
# - do not freeze orders and do not create accounting documents

COMPANY = "Doh Myot Daw BBQ & Restaurant"
POS_PROFILE = "DMT"

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
    frappe.throw("You are not allowed to view cashier billing.")

action = (frappe.form_dict.get("action") or "").strip()
if action:
    frappe.throw("Unsupported cashier billing action: " + action)

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
        "net_total",
        "total_taxes_and_charges",
        "grand_total",
        "currency",
        "custom_restaurant_status",
    ],
    order_by="creation asc",
    limit_page_length=500,
)

has_print_job_doctype = bool(frappe.db.exists("DocType", "BCN Print Job"))
bills = []

for order in orders:
    sales_order = frappe.get_doc("Sales Order", order.name)

    item_rows = []
    for item in sales_order.items:
        item_rows.append(
            {
                "item_code": item.item_code,
                "item_name": item.item_name,
                "description": item.description,
                "qty": float(item.qty or 0),
                "uom": item.uom,
                "rate": float(item.rate or 0),
                "amount": float(item.amount or 0),
                "net_amount": float(item.net_amount or 0),
            }
        )

    tax_rows = []
    for tax in sales_order.taxes:
        tax_rows.append(
            {
                "charge_type": tax.charge_type,
                "account_head": tax.account_head,
                "description": tax.description,
                "rate": float(tax.rate or 0),
                "tax_amount": float(tax.tax_amount or 0),
                "total": float(tax.total or 0),
            }
        )

    last_print_status = None
    last_print_job = None

    if has_print_job_doctype:
        print_rows = frappe.get_all(
            "BCN Print Job",
            filters={
                "document_type": "Sales Order",
                "document_name": order.name,
            },
            fields=["name", "status"],
            order_by="creation desc",
            limit_page_length=1,
        )
        if print_rows:
            last_print_job = print_rows[0].name
            last_print_status = print_rows[0].status

    bills.append(
        {
            "sales_order": order.name,
            "customer": order.customer,
            "customer_name": order.customer_name or order.customer,
            "creation": str(order.creation),
            "net_total": float(order.net_total or 0),
            "total_taxes_and_charges": float(order.total_taxes_and_charges or 0),
            "grand_total": float(order.grand_total or 0),
            "currency": order.currency,
            "restaurant_status": order.custom_restaurant_status,
            "last_print_status": last_print_status,
            "last_print_job": last_print_job,
            "items": item_rows,
            "taxes": tax_rows,
        }
    )

profile = frappe.get_doc("POS Profile", POS_PROFILE)
modes = []
seen_modes = []

for payment in profile.payments:
    mode_name = (payment.mode_of_payment or "").strip()
    if mode_name and mode_name not in seen_modes:
        seen_modes.append(mode_name)
        modes.append(
            {
                "name": mode_name,
                "default": bool(payment.default),
            }
        )

frappe.response["message"] = {
    "bills": bills,
    "modes": modes,
}
