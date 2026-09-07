# Server Script API: bcn_mobile_menu
# Deployment target: https://ourcity.s.frappe.cloud

COMPANY = "Doh Myot Daw BBQ & Restaurant"
POS_PROFILE = "DMT"
PRICE_LIST = "Standard Selling"
CURRENCY = "MMK"

current_user = frappe.session.user

if not current_user or current_user == "Guest":
    frappe.throw("Authentication is required.")

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

        rate = 0
        for price in price_rows:
            if not price.uom or price.uom == item.stock_uom:
                rate = frappe.utils.flt(price.price_list_rate)
                break

        items_out.append(
            {
                "item_code": item.item_code,
                "item_name": item.item_name,
                "item_group": item.item_group,
                "uom": item.stock_uom,
                "rate": rate,
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
