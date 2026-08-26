from __future__ import annotations

import frappe

from bcn_restaurant.api.common import get_settings, require_any_role
from bcn_restaurant.services.menu import get_active_item_price


@frappe.whitelist()
def get_menu():
    require_any_role("Waiter", "Cashier", "Kitchen")
    settings = get_settings()
    pos_profile = frappe.get_cached_doc("POS Profile", settings["pos_profile"])
    item_groups = [row.item_group for row in pos_profile.item_groups if row.item_group]

    if not item_groups:
        return {
            "price_list": settings["selling_price_list"],
            "currency": settings["default_currency"],
            "groups": [],
            "items": [],
        }

    items = frappe.get_all(
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
            "custom_kitchen_counter",
        ],
        order_by="item_group asc, item_name asc",
    )

    output = []
    for item in items:
        try:
            rate = get_active_item_price(
                item_code=item.item_code,
                price_list=settings["selling_price_list"],
                uom=item.stock_uom,
            )
        except frappe.ValidationError:
            continue

        output.append(
            {
                "item_code": item.item_code,
                "item_name": item.item_name,
                "item_group": item.item_group,
                "uom": item.stock_uom,
                "image": item.image,
                "is_stock_item": bool(item.is_stock_item),
                "kitchen_counter": item.custom_kitchen_counter,
                "rate": rate,
                "currency": settings["default_currency"],
            }
        )

    return {
        "price_list": settings["selling_price_list"],
        "currency": settings["default_currency"],
        "groups": item_groups,
        "items": output,
    }
