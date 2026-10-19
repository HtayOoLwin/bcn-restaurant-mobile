# Server Script API: bcn_mobile_menu
# Deployment target: https://ourcity.s.frappe.cloud

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
    frappe.throw(
        "You are not allowed to use waiter restaurant views."
    )

profile = frappe.get_doc("POS Profile", POS_PROFILE)

item_groups = []
for row in profile.item_groups:
    if row.item_group and row.item_group not in item_groups:
        item_groups.append(row.item_group)

items_out = []

if item_groups:
    item_rows = frappe.get_all(
        "Item",
        filters={
            "item_group": ["in", item_groups],
            "disabled": 0,
            "is_sales_item": 1,
        },
        fields=[
            "name as item_code",
            "item_name",
            "item_group",
            "stock_uom",
            "image",
            "is_stock_item",
        ],
        order_by="item_group asc, item_name asc",
        limit_page_length=1000,
    )

    for item in item_rows:
        price_rows = frappe.get_all(
            "Item Price",
            filters={
                "price_list": PRICE_LIST,
                "item_code": item.item_code,
            },
            fields=["price_list_rate", "uom"],
            order_by="modified desc",
            limit_page_length=20,
        )

        factors = {item.stock_uom: 1.0}
        conversion_rows = frappe.get_all(
            "UOM Conversion Detail",
            filters={"parent": item.item_code, "parenttype": "Item"},
            fields=["uom", "conversion_factor"],
            limit_page_length=100,
        )
        for conversion in conversion_rows:
            factor = frappe.utils.flt(conversion.conversion_factor)
            if conversion.uom and factor > 0:
                factors[conversion.uom] = factor

        options = []
        seen_uoms = []
        for price in price_rows:
            unit = (price.uom or item.stock_uom).strip()
            if unit in factors and unit not in seen_uoms:
                seen_uoms.append(unit)
                options.append({
                    "uom": unit,
                    "rate": frappe.utils.flt(price.price_list_rate),
                    "conversion_factor": factors[unit],
                })
        if not options:
            continue
        primary = next(
            (option for option in options if option["uom"] == item.stock_uom),
            options[0],
        )

        items_out.append(
            {
                "item_code": item.item_code,
                "item_name": item.item_name,
                "item_group": item.item_group,
                "uom": primary["uom"],
                "rate": primary["rate"],
                "uoms": options,
                "currency": CURRENCY,
                "is_stock_item": bool(item.is_stock_item),
                "image": item.image,
            }
        )

frappe.response["message"] = {
    "price_list": PRICE_LIST,
    "currency": CURRENCY,
    "groups": item_groups,
    "items": items_out,
}
