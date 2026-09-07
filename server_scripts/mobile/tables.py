# Server Script API: bcn_mobile_tables
# Deployment target: https://ourcity.s.frappe.cloud

COMPANY = "Doh Myot Daw BBQ & Restaurant"
PRICE_LIST = "Standard Selling"
CURRENCY = "MMK"

current_user = frappe.session.user
if not current_user or current_user == "Guest":
    frappe.throw("Authentication is required.")

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

open_orders = frappe.get_all(
    "Sales Order",
    filters={
        "docstatus": 0,
        "custom_restaurant_status": ["in", ["Open", "Billing"]],
    },
    fields=[
        "name",
        "customer",
        "custom_restaurant_status",
        "creation",
    ],
    order_by="creation asc",
    limit_page_length=500,
)

order_by_customer = {}
for order in open_orders:
    if order.customer not in order_by_customer:
        order_by_customer[order.customer] = order

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
