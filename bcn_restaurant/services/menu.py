from __future__ import annotations

from typing import Any

import frappe
from frappe.utils import getdate, nowdate


def get_active_item_price(
    item_code: str,
    price_list: str,
    uom: str | None = None,
    on_date: str | None = None,
) -> float:
    """Return the active selling rate from Item Price.

    The mobile client never supplies an authoritative rate. We deliberately
    resolve the price on the server for both menu display and order creation.
    """
    target_date = getdate(on_date or nowdate())
    filters: dict[str, Any] = {
        "item_code": item_code,
        "price_list": price_list,
        "selling": 1,
    }

    rows = frappe.get_all(
        "Item Price",
        filters=filters,
        fields=["price_list_rate", "uom", "valid_from", "valid_upto", "modified"],
        order_by="valid_from desc, modified desc",
        limit=50,
    )

    candidates = []
    for row in rows:
        if row.valid_from and getdate(row.valid_from) > target_date:
            continue
        if row.valid_upto and getdate(row.valid_upto) < target_date:
            continue
        if uom and row.uom and row.uom != uom:
            continue
        candidates.append(row)

    if not candidates:
        frappe.throw(f"No active price found for item {item_code} in {price_list}")

    return float(candidates[0].price_list_rate or 0)
