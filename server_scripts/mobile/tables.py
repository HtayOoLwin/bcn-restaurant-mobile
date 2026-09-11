# Server Script API: bcn_mobile_tables
# Deployment target: https://ourcity.s.frappe.cloud

COMPANY = "Doh Myot Daw BBQ & Restaurant"
PRICE_LIST = "Standard Selling"
CURRENCY = "MMK"

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
    frappe.throw(
        "You are not allowed to use waiter restaurant views."
    )

service_type = (frappe.form_dict.get("service_type") or "dine_in").strip().lower()

if service_type in ("dine_in", "dinein"):
    service_type = "dine_in"
    customer_group = "Dine In"
elif service_type == "takeaway":
    customer_group = "Takeaway"
else:
    frappe.throw("service_type must be dine_in or takeaway")

customers = frappe.get_all(
    "Customer",
    filters={
        "customer_group": customer_group,
        "disabled": 0,
    },
    fields=["name", "customer_name", "customer_group"],
    order_by="customer_name asc, name asc",
    limit_page_length=200,
)

active_orders = frappe.get_all(
    "Sales Order",
    filters={
        "docstatus": ["in", [0, 1]],
        "custom_restaurant_status": ["in", ["Open", "Billing"]],
    },
    fields=[
        "name",
        "customer",
        "docstatus",
        "custom_restaurant_status",
        "creation",
    ],
    order_by="creation asc",
    limit_page_length=500,
)

order_by_customer = {}
for row in active_orders:
    valid_open = (
        row.docstatus == 0
        and row.custom_restaurant_status == "Open"
    )
    valid_billing = (
        row.docstatus == 1 and row.custom_restaurant_status == "Billing"
    )
    if not valid_open and not valid_billing:
        continue

    existing = order_by_customer.get(row.customer)
    if not existing:
        order_by_customer[row.customer] = row
    elif row.custom_restaurant_status == "Billing":
        # A submitted Billing order must win over any stale Draft Open row so
        # the table cannot appear Available/Occupied for new ordering.
        order_by_customer[row.customer] = row

result = []
for customer in customers:
    order = order_by_customer.get(customer.name)

    table_status = "Available"
    is_open = False
    sales_order = None
    opened_at = None

    if order:
        is_open = True
        sales_order = order.name
        opened_at = order.creation
        if order.custom_restaurant_status == "Billing":
            table_status = "Billing"
        else:
            table_status = "Occupied"

    result.append(
        {
            "customer": customer.name,
            "customer_name": customer.customer_name,
            "customer_group": customer.customer_group,
            "is_open": is_open,
            "session": sales_order,
            "session_status": table_status,
            "waiter": None,
            "opened_at": opened_at,
        }
    )

frappe.response["message"] = {
    "service_type": service_type,
    "customer_group": customer_group,
    "tables": result,
}
