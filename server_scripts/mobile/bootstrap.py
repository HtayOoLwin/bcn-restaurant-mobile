# Server Script API: bcn_mobile_bootstrap
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

is_administrator = current_user == "Administrator" or "Admin" in roles
is_manager = (
    is_administrator
    or "System Manager" in roles
    or "Restaurant Manager" in roles
)
is_waiter = is_manager or "Waiter" in roles
is_cashier = is_manager or "Cashier" in roles

full_name = frappe.db.get_value("User", current_user, "full_name") or current_user

frappe.response["message"] = {
    "user": current_user,
    "full_name": full_name,
    "roles": roles,
    "permissions": {
        "waiter": is_waiter,
        "cashier": is_cashier,
        "manager": is_manager,
        "can_request_cashier_print": is_cashier or is_manager,
        "can_view_print_status": is_cashier or is_manager,
        "can_retry_print_jobs": is_manager,
    },
    "company": COMPANY,
    "currency": CURRENCY,
    "selling_price_list": PRICE_LIST,
    "kitchen_counters": [],
}
