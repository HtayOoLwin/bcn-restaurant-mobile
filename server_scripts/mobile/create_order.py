# Server Script API: bcn_mobile_create_order
# Deployment target: https://ourcity.s.frappe.cloud
#
# Restaurant flow:
# - one Open Draft Sales Order per table/customer
# - later orders reuse the same Draft Sales Order
# - Draft Billing permits additions; each addition invalidates the old bill
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
    or "Admin" in roles
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

active_orders = frappe.get_all(
    "Sales Order",
    filters={
        "customer": customer,
        "docstatus": ["in", [0, 1]],
        "custom_restaurant_status": ["in", ["Open", "Billing"]],
    },
    fields=[
        "name",
        "docstatus",
        "custom_client_order_id",
        "grand_total",
        "custom_restaurant_status",
    ],
    order_by="creation asc",
    limit_page_length=5,
)

billing_orders = []
open_draft_orders = []
for active_order in active_orders:
    if active_order.custom_restaurant_status == "Billing" and active_order.docstatus == 1:
        billing_orders.append(active_order)
    if (
        active_order.docstatus == 0
        and active_order.custom_restaurant_status in ["Open", "Billing"]
    ):
        open_draft_orders.append(active_order)

if billing_orders and any(order.docstatus == 1 for order in billing_orders):
    frappe.throw("Table is already submitted for payment: " + customer)

if len(open_draft_orders) > 1:
    frappe.throw(
        "More than one active Draft Sales Order exists for "
        + customer
        + ". Please check ERPNext."
    )

is_new_order = not bool(open_draft_orders)

if is_new_order:
    sales_order = frappe.new_doc("Sales Order")
else:
    sales_order = frappe.get_doc("Sales Order", open_draft_orders[0].name)

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
        sales_order.custom_check_in = frappe.utils.now_datetime()

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

        is_room_charge = bool(item.get("custom_is_room_charge"))
        if is_room_charge:
            if item.is_stock_item:
                frappe.throw("Room charge must be a non-stock Item: " + item_code)
            if requested_uom and requested_uom != "Hour":
                frappe.throw("Room charge UOM must be Hour")
            if any(bool(frappe.db.get_value("Item", row.item_code, "custom_is_room_charge")) for row in sales_order.items):
                frappe.throw("Only one Room Charge Item is permitted per Sales Order")
            qty = 1.0  # provisional: Request for Bill calculates duration
        kitchen_counter = "" if is_room_charge else (item.get("custom_kitchen_counter") or "").strip()
        uom = "Hour" if is_room_charge else (requested_uom or item.stock_uom)

        conversion_factor = 1.0
        if uom != item.stock_uom:
            factor_row = frappe.db.get_value(
                "UOM Conversion Detail",
                {"parent": item_code, "parenttype": "Item", "uom": uom},
                "conversion_factor",
            )
            conversion_factor = frappe.utils.flt(factor_row)
            if conversion_factor <= 0:
                frappe.throw("UOM " + uom + " is not configured for " + item_code)

        price_rows = frappe.get_all(
            "Item Price",
            filters={"price_list": PRICE_LIST, "item_code": item_code},
            fields=["price_list_rate", "uom"],
            order_by="modified desc",
            limit_page_length=100,
        )
        rate = None
        for price in price_rows:
            price_uom = (price.uom or item.stock_uom).strip()
            if price_uom == uom:
                rate = frappe.utils.flt(price.price_list_rate)
                break
        if rate is None:
            frappe.throw("No " + PRICE_LIST + " Item Price for " + item_code + " / " + uom)

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
            matching_row.conversion_factor = conversion_factor
            matching_row.custom_kitchen_counter = kitchen_counter
        else:
            # Validate and append a NEW row separately; this path differs
            # from increasing the quantity of an existing SO Item.
            try:
                sales_order.append(
                    "items",
                    {
                        "item_code": item_code,
                        "item_name": item.item_name,
                        "description": description,
                        "qty": qty,
                        "uom": uom,
                        "stock_uom": item.stock_uom,
                        "conversion_factor": conversion_factor,
                        "rate": rate,
                        "delivery_date": frappe.utils.getdate(today),
                        "custom_kitchen_note": kitchen_note,
                        "custom_kitchen_counter": kitchen_counter,
                        "custom_printed_qty": 0,
                    },
                )
            except Exception as error:
                frappe.throw("CREATE ORDER NEW ITEM [" + item_code + "]: " + str(error))

    if not sales_order.items:
        frappe.throw("Sales Order has no items.")

    if profile.taxes_and_charges and not sales_order.taxes_and_charges:
        sales_order.taxes_and_charges = profile.taxes_and_charges

    if sales_order.taxes_and_charges and not sales_order.taxes:
        # Read the selected template directly. The ERPNext Python method
        # erpnext.accounts.services.taxes.get_taxes_and_charges is not
        # available on every deployed ERPNext version.
        tax_template = frappe.get_doc(
            "Sales Taxes and Charges Template",
            sales_order.taxes_and_charges,
        )
        if tax_template.company and tax_template.company != COMPANY:
            frappe.throw("Sales Tax Template company does not match")

        for template_row in tax_template.taxes:
            tax_values = {
                "charge_type": template_row.charge_type,
                "account_head": template_row.account_head,
                "description": template_row.description,
                "rate": template_row.rate,
                "tax_amount": template_row.tax_amount,
                "row_id": template_row.row_id,
                "included_in_print_rate": template_row.included_in_print_rate,
                "cost_center": template_row.cost_center,
            }
            sales_order.append("taxes", tax_values)

    try:
        sales_order.calculate_taxes_and_totals()
    except Exception as error:
        frappe.throw("CREATE ORDER TOTALS: " + str(error))
    sales_order.custom_client_order_id = client_order_id
    sales_order.custom_restaurant_status = "Open"
    if not sales_order.get("custom_check_in"):
        sales_order.custom_check_in = sales_order.creation or frappe.utils.now_datetime()
    sales_order.flags.ignore_permissions = True

    try:
        if is_new_order:
            sales_order.insert(ignore_permissions=True)
        else:
            sales_order.save(ignore_permissions=True)
    except Exception as error:
        frappe.throw("CREATE ORDER SAVE: " + str(error))

frappe.response["message"] = {
    "sales_order": sales_order.name,
    "session": "",
    "grand_total": float(sales_order.grand_total or 0),
    "preparation_summary": "New",
    "duplicate": is_duplicate,
}
