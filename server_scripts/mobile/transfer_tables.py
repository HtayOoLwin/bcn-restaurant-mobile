# Server Script API: bcn_mobile_transfer_tables
# Lists eligible empty tables; does not change any order.
POS_PROFILE = "DMT"
user = frappe.session.user
if not user or user == "Guest":
    frappe.throw("Authentication required")
roles = frappe.get_roles(user)
if not (user == "Administrator" or "System Manager" in roles or "Admin" in roles or "Waiter" in roles or "Restaurant Manager" in roles):
    frappe.throw("Not allowed to transfer tables")

profile = frappe.get_doc("POS Profile", POS_PROFILE)
company = (profile.company or "").strip()
if not company:
    frappe.throw("POS Profile company is missing")

from_customer = (frappe.form_dict.get("from_customer") or "").strip()
if not from_customer:
    frappe.throw("Current table is required")
source = frappe.db.get_value(
    "Customer", from_customer,
    ["name", "customer_name", "customer_group", "disabled"],
    as_dict=True
)
if not source or source.disabled or source.customer_group in ("Takeaway", "Credit"):
    frappe.throw("Current table is not an active dining table")

# A table is represented by a Customer in this restaurant installation.
# Include empty physical dining tables across AC / Dine In areas.
# Keep existing order rates, room charges and tax totals unchanged.
customers = frappe.get_all(
    "Customer",
    filters={
        "disabled": 0,
        "customer_group": ["not in", ["Takeaway", "Credit"]],
    },
    fields=["name", "customer_name", "customer_group"],
    order_by="customer_name asc",
    limit_page_length=1000,
)
active_orders = frappe.get_all(
    "Sales Order",
    filters={
        "company": company,
        "docstatus": ["in", [0, 1]],
        "custom_restaurant_status": ["in", ["Open", "Billing", "Payment Pending"]],
        "customer": ["in", [row.name for row in customers]],
    },
    fields=["customer", "name"],
    limit_page_length=5000,
) if customers else []
occupied = {row.customer for row in active_orders}
tables = []
for customer in customers:
    if customer.name == from_customer or customer.name in occupied:
        continue
    tables.append({
        "customer": customer.name,
        "customer_name": customer.customer_name or customer.name,
        "customer_group": customer.customer_group,
        "is_open": False,
        "session": None,
        "session_status": "Available",
    })

frappe.response["message"] = {
    "success": True,
    "from_customer": from_customer,
    "tables": tables,
}
