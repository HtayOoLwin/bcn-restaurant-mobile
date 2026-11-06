# Server Script API: bcn_mobile_transfer_table
# Transfers only the table/customer on an Open Draft Sales Order.
# No history, no new order, no item/price/print changes.

user = frappe.session.user
if not user or user == "Guest":
    frappe.throw("Authentication required")
roles = frappe.get_roles(user)
if not (user == "Administrator" or "System Manager" in roles or "Admin" in roles or "Waiter" in roles or "Restaurant Manager" in roles):
    frappe.throw("Not allowed to transfer tables")

profile = frappe.get_doc("POS Profile", "DMT")
company = (profile.company or "").strip()
if not company:
    frappe.throw("POS Profile DMT must have a Company")

sales_order = (frappe.form_dict.get("sales_order") or "").strip()
from_customer = (frappe.form_dict.get("from_customer") or "").strip()
to_customer = (frappe.form_dict.get("to_customer") or "").strip()
if not sales_order or not from_customer or not to_customer:
    frappe.throw("sales_order, from_customer and to_customer are required")
if from_customer == to_customer:
    frappe.throw("Please select a different destination table")

# Serialize transfers and new orders per table. Creation API must use
# the same Customer-row lock to prevent cross-request races.
for customer_name in sorted([from_customer, to_customer]):
    locked_customer = frappe.db.sql(
        "SELECT name FROM `tabCustomer` WHERE name=%(name)s FOR UPDATE",
        {"name": customer_name},
        as_dict=True,
    )
    if not locked_customer:
        frappe.throw("Table does not exist: " + customer_name)

locked_order = frappe.db.sql(
    "SELECT name FROM `tabSales Order` WHERE name=%(name)s FOR UPDATE",
    {"name": sales_order},
    as_dict=True,
)
if not locked_order:
    frappe.throw("Sales Order not found")

order = frappe.get_doc("Sales Order", sales_order)
if order.company != company:
    frappe.throw("Sales Order company does not match POS Profile")
if order.customer != from_customer:
    frappe.throw("Table has changed. Please refresh the dashboard")
if order.docstatus != 0 or order.custom_restaurant_status != "Open":
    frappe.throw("Only Open Draft Sales Orders can be transferred")

source = frappe.db.get_value(
    "Customer", from_customer,
    ["name", "customer_group", "disabled"], as_dict=True
)
destination = frappe.db.get_value(
    "Customer", to_customer,
    ["name", "customer_name", "customer_group", "disabled"], as_dict=True
)
if not source or source.disabled or not destination or destination.disabled:
    frappe.throw("Source or destination table is disabled")
if source.customer_group not in ("AC", "Dine In") or destination.customer_group not in ("AC", "Dine In"):
    frappe.throw("Source and destination must be AC or Dine In tables")

# Recheck availability AFTER the row locks. This includes submitted bills.
occupied = frappe.get_all(
    "Sales Order",
    filters={
        "company": company,
        "customer": to_customer,
        "docstatus": ["in", [0, 1]],
        "custom_restaurant_status": ["in", ["Open", "Billing", "Payment Pending"]],
    },
    fields=["name"],
    limit_page_length=1,
)
if occupied:
    frappe.throw("Destination table is no longer available. Refresh and try again")

# Match the strict one-order-per-table expectation.
source_orders = frappe.get_all(
    "Sales Order",
    filters={
        "company": company,
        "customer": from_customer,
        "docstatus": ["in", [0, 1]],
        "custom_restaurant_status": ["in", ["Open", "Billing", "Payment Pending"]],
    },
    fields=["name"],
    limit_page_length=3,
)
if len(source_orders) != 1 or source_orders[0].name != sales_order:
    frappe.throw("Source table has another active order. Please refresh")

# Table is mapped to Customer in this restaurant. Change ONLY these two
# Sales Order header fields to preserve items, totals, time and print flags.
frappe.db.set_value(
    "Sales Order",
    sales_order,
    {
        "customer": to_customer,
        "customer_name": destination.customer_name or to_customer,
    },
    update_modified=True,
)

frappe.response["message"] = {
    "success": True,
    "sales_order": sales_order,
    "from_customer": from_customer,
    "to_customer": to_customer,
    "to_table": destination.customer_name or to_customer,
    "message": "Table transferred successfully",
}
