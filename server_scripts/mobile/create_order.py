# Server Script API: bcn_mobile_create_order
# Deployment target: https://ourcity.s.frappe.cloud
#
# Restaurant flow:
# - one Open Draft Sales Order per table/customer
# - later orders reuse the same Draft Sales Order
# - Billing locks the table against new waiter orders
# - Sales Order Item stores kitchen note, kitchen counter snapshot, printed qty
# - this script does not submit the Sales Order and does not print directly

COMPANY = "Doh Myot Daw BBQ & Restaurant"
POS_PROFILE = "DMT"
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
    or "System Manager" in roles
    or "Waiter" in roles
    or "Restaurant Manager" in roles
)

if not allowed_user:
    frappe.throw("You are not allowed to create restaurant orders.")

customer = (frappe.form_dict.get("customer") or "").strip()
client_order_id = (frappe.form_dict.get("client_order_id") or "").strip()
raw_items = frappe.form_dict.get("items")

if not customer:
    frappe.throw("Customer / Table is required.")

if not client_order_id:
    frappe.throw("Client Order ID is required.")

items = json.loads(raw_items) if raw_items else []
if not items:
    frappe.throw("Order must contain at least one item.")

customer_row = frappe.db.get_value(
    "Customer",
    customer,
    ["name", "customer_name", "customer_group", "disabled"],
    as_dict=True,
)

if not customer_row:
    frappe.throw("Customer / Table not found: " + customer)

if customer_row.disabled:
    frappe.throw("Customer / Table is disabled: " + customer)

if customer_row.customer_group not in ("Dine In", "Takeaway"):
    frappe.throw("Customer must belong to Dine In or Takeaway Customer Group.")

active_orders = frappe.get_all(
    "Sales Order",
    filters={
        "customer": customer,
        "docstatus": 0,
        "custom_restaurant_status": ["in", ["Open", "Billing"]],
    },
    fields=[
        "name",
        "custom_client_order_id",
        "grand_total",
        "custom_restaurant_status",
    ],
    order_by="creation asc",
    limit_page_length=2,
)

if len(active_orders) > 1:
    frappe.throw(
        "More than one active Draft Sales Order exists for "
        + customer
        + ". Please check ERPNext."
    )

if active_orders and active_orders[0].custom_restaurant_status == "Billing":
    frappe.throw("Table is currently in Billing: " + customer)

is_new_order = not bool(active_orders)

if is_new_order:
    sales_order = frappe.new_doc("Sales Order")
else:
    sales_order = frappe.get_doc("Sales Order", active_orders[0].name)

existing_client_order_id = (
    sales_order.get("custom_client_order_id") or ""
).strip()
is_duplicate = (not is_new_order) and existing_client_order_id == client_order_id

if not is_duplicate:
    profile = frappe.get_doc("POS Profile", POS_PROFILE)
    today = frappe.utils.nowdate()

    if is_new_order:
        sales_order.company = COMPANY
        sales_order.customer = customer
        sales_order.transaction_date = today
        sales_order.delivery_date = today
        sales_order.selling_price_list = PRICE_LIST
        sales_order.price_list_currency = CURRENCY
        sales_order.currency = CURRENCY
        sales_order.conversion_rate = 1
        sales_order.plc_conversion_rate = 1
        sales_order.custom_restaurant_status = "Open"

        if profile.warehouse:
            sales_order.set_warehouse = profile.warehouse

    allowed_item_groups = []
    for group_row in profile.item_groups:
        if (
            group_row.item_group
            and group_row.item_group not in allowed_item_groups
        ):
            allowed_item_groups.append(group_row.item_group)

    if not allowed_item_groups:
        frappe.throw("POS Profile DMT has no Item Groups.")

    for payload in items:
        item_code = (payload.get("item_code") or "").strip()
        qty = frappe.utils.flt(payload.get("qty"))
        requested_uom = (payload.get("uom") or "").strip()
        kitchen_note = (payload.get("kitchen_note") or "").strip()

        if not item_code:
            frappe.throw("Item Code is required.")

        if qty <= 0:
            frappe.throw("Quantity must be greater than zero for " + item_code)

        if not frappe.db.exists("Item", item_code):
            frappe.throw("Item " + item_code + " not found")

        item = frappe.get_doc("Item", item_code)

        if item.disabled:
            frappe.throw("Item is disabled: " + item_code)

        if not item.is_sales_item:
            frappe.throw("Item is not available for sale: " + item_code)

        if item.item_group not in allowed_item_groups:
            frappe.throw("Item is not allowed in POS Profile DMT: " + item_code)

        kitchen_counter = (item.get("custom_kitchen_counter") or "").strip()
        uom = requested_uom or item.stock_uom

        if uom != item.stock_uom:
            frappe.throw(
                "Please use Stock UOM "
                + item.stock_uom
                + " for item "
                + item_code
            )

        price_rows = frappe.get_all(
            "Item Price",
            filters={
                "price_list": PRICE_LIST,
                "item_code": item_code,
            },
            fields=["price_list_rate", "uom"],
            order_by="modified desc",
            limit_page_length=20,
        )

        rate = None
        for price in price_rows:
            if not price.uom or price.uom == uom:
                rate = frappe.utils.flt(price.price_list_rate)
                break

        if rate is None:
            frappe.throw("No Standard Selling Item Price found for " + item_code)

        description = item.description or item.item_name or item_code
        matching_row = None

        for existing_row in sales_order.items:
            existing_note = (
                existing_row.get("custom_kitchen_note") or ""
            ).strip()
            existing_counter = (
                existing_row.get("custom_kitchen_counter") or ""
            ).strip()

            if (
                existing_row.item_code == item_code
                and existing_row.uom == uom
                and existing_note == kitchen_note
                and existing_counter == kitchen_counter
            ):
                matching_row = existing_row
                break

        if matching_row:
            matching_row.qty = frappe.utils.flt(matching_row.qty) + qty
            matching_row.rate = rate
            matching_row.custom_kitchen_counter = kitchen_counter
        else:
            sales_order.append(
                "items",
                {
                    "item_code": item_code,
                    "item_name": item.item_name,
                    "description": description,
                    "qty": qty,
                    "uom": uom,
                    "stock_uom": item.stock_uom,
                    "conversion_factor": 1,
                    "rate": rate,
                    "delivery_date": today,
                    "custom_kitchen_note": kitchen_note,
                    "custom_kitchen_counter": kitchen_counter,
                    "custom_printed_qty": 0,
                },
            )

    if not sales_order.items:
        frappe.throw("Sales Order has no items.")

    sales_order.custom_client_order_id = client_order_id
    sales_order.custom_restaurant_status = "Open"
    sales_order.flags.ignore_permissions = True

    if is_new_order:
        sales_order.insert(ignore_permissions=True)
    else:
        sales_order.save(ignore_permissions=True)

frappe.response["message"] = {
    "sales_order": sales_order.name,
    "session": "",
    "grand_total": float(sales_order.grand_total or 0),
    "preparation_summary": "New",
    "duplicate": is_duplicate,
}
