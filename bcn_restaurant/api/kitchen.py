from __future__ import annotations

import frappe
from frappe.utils import now_datetime

from bcn_restaurant.api.common import get_user_kitchen_counters, require_any_role
from bcn_restaurant.domain.preparation import kitchen_next_status
from bcn_restaurant.services.preparation import (
    assert_active_restaurant_order,
    get_active_session_order_names,
    recalculate_sales_order,
)

ACTIVE_ITEM_STATES = ("New", "Accepted", "Preparing", "Ready")


@frappe.whitelist()
def get_orders(status: str | None = None):
    require_any_role("Kitchen")
    counters = get_user_kitchen_counters()
    if not counters:
        frappe.throw("No Kitchen Counter permission is assigned to this user")

    requested_status = (status or "").strip()
    if requested_status and requested_status not in ACTIVE_ITEM_STATES:
        frappe.throw("status must be New, Accepted, Preparing, or Ready")

    order_names = get_active_session_order_names()
    if not order_names:
        return {"orders": [], "count": 0, "item_count": 0, "allowed_counters": counters}

    filters = {
        "parent": ["in", order_names],
        "parenttype": "Sales Order",
        "docstatus": 1,
        "custom_kitchen_counter": ["in", counters],
        "custom_preparation_status": ["in", [requested_status] if requested_status else list(ACTIVE_ITEM_STATES)],
    }
    item_rows = frappe.get_all(
        "Sales Order Item",
        filters=filters,
        fields=[
            "name", "parent", "idx", "item_code", "item_name", "qty", "uom", "warehouse",
            "custom_kitchen_counter", "custom_preparation_status", "custom_kitchen_note", "creation",
        ],
        order_by="creation asc, parent asc, idx asc",
        limit_page_length=1000,
    )

    parents = list(dict.fromkeys(row.parent for row in item_rows))
    headers = {}
    if parents:
        for row in frappe.get_all(
            "Sales Order",
            filters={"name": ["in", parents], "docstatus": 1},
            fields=["name", "customer", "creation", "custom_preparation_summary", "custom_restaurant_session"],
            order_by="creation asc",
            limit_page_length=1000,
        ):
            headers[row.name] = row

    grouped: dict[str, dict] = {}
    for row in item_rows:
        header = headers.get(row.parent)
        if not header:
            continue
        group = grouped.setdefault(
            row.parent,
            {
                "name": header.name,
                "customer": header.customer,
                "creation": header.creation,
                "session": header.custom_restaurant_session,
                "preparation_summary": header.custom_preparation_summary or "New",
                "items": [],
            },
        )
        group["items"].append(
            {
                "row_name": row.name,
                "item_code": row.item_code,
                "item_name": row.item_name or row.item_code,
                "qty": float(row.qty or 0),
                "uom": row.uom,
                "warehouse": row.warehouse,
                "kitchen_counter": row.custom_kitchen_counter,
                "preparation_status": row.custom_preparation_status or "New",
                "kitchen_note": row.custom_kitchen_note,
                "created_at": row.creation,
            }
        )

    orders = [grouped[name] for name in parents if name in grouped]
    return {
        "orders": orders,
        "count": len(orders),
        "item_count": len(item_rows),
        "allowed_counters": counters,
    }


@frappe.whitelist(methods=["POST"])
def update_item_status(item_row_name: str, action: str):
    require_any_role("Kitchen")
    counters = get_user_kitchen_counters()
    if not counters:
        frappe.throw("No Kitchen Counter permission is assigned to this user")

    row = frappe.get_doc("Sales Order Item", item_row_name)
    if row.parenttype != "Sales Order":
        frappe.throw("Invalid Sales Order Item")
    if row.custom_kitchen_counter not in counters:
        frappe.throw("You are not permitted to update this kitchen counter item", frappe.PermissionError)

    order = frappe.get_doc("Sales Order", row.parent)
    session = assert_active_restaurant_order(order)
    current_status = row.custom_preparation_status or "New"
    try:
        next_status = kitchen_next_status(current_status, action)
    except ValueError as exc:
        frappe.throw(str(exc))

    values = {"custom_preparation_status": next_status}
    if next_status == "Ready":
        values.update({
            "custom_prepared_qty": row.qty,
            "custom_ready_at": now_datetime(),
        })
    frappe.db.set_value("Sales Order Item", row.name, values, update_modified=True)

    if next_status == "Ready":
        _notify_waiter_ready(order, session, row)

    summary = recalculate_sales_order(order.name)
    return {
        "sales_order": order.name,
        "row_name": row.name,
        "status": next_status,
        "preparation_summary": summary["summary"],
    }


def _notify_waiter_ready(order, session, row) -> None:
    recipient = session.waiter or order.owner
    if not recipient or recipient in {"Guest", "Administrator"}:
        return

    title = f"Ready to Pick Up · {order.customer} · {row.item_name or row.item_code} · {row.name}"
    if frappe.db.exists("Notification Log", {"for_user": recipient, "title": title}):
        return

    frappe.get_doc(
        {
            "doctype": "Notification Log",
            "for_user": recipient,
            "from_user": frappe.session.user,
            "title": title,
            "description": (
                f"{row.item_name or row.item_code} is ready at "
                f"{row.custom_kitchen_counter or 'Kitchen'}. Order: {order.name}"
            ),
            "document_type": "Sales Order",
            "document_name": order.name,
            "link": "/waiter-orders",
            "read": 0,
        }
    ).insert(ignore_permissions=True)
