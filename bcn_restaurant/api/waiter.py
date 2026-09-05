from __future__ import annotations

import frappe
from frappe.utils import now_datetime

from bcn_restaurant.api.common import current_roles, require_any_role
from bcn_restaurant.domain.preparation import can_serve_whole
from bcn_restaurant.services.preparation import (
    assert_active_restaurant_order,
    get_active_session_order_names,
    recalculate_sales_order,
)


def _is_manager() -> bool:
    roles = set(current_roles())
    return bool(roles.intersection({"Administrator", "Restaurant Manager", "System Manager"}))


def _current_waiter_filter() -> str | None:
    return None if _is_manager() else frappe.session.user


def _active_order_names() -> list[str]:
    return get_active_session_order_names(waiter=_current_waiter_filter())


@frappe.whitelist()
def get_order_progress():
    require_any_role("Waiter", "Restaurant Manager")
    order_names = _active_order_names()
    if not order_names:
        return {"orders": [], "count": 0, "user": frappe.session.user}

    orders = frappe.get_all(
        "Sales Order",
        filters={"name": ["in", order_names], "docstatus": 1},
        fields=[
            "name", "customer", "customer_name", "creation", "grand_total",
            "custom_preparation_summary", "custom_restaurant_session",
        ],
        order_by="creation asc",
        limit_page_length=1000,
    )
    items = frappe.get_all(
        "Sales Order Item",
        filters={"parent": ["in", order_names], "parenttype": "Sales Order", "docstatus": 1},
        fields=[
            "name", "parent", "idx", "item_code", "item_name", "qty", "uom",
            "custom_kitchen_counter", "custom_preparation_status", "custom_kitchen_note",
            "custom_ready_at", "custom_served_at",
        ],
        order_by="parent asc, idx asc",
        limit_page_length=5000,
    )
    items_by_order: dict[str, list] = {}
    for row in items:
        items_by_order.setdefault(row.parent, []).append(row)

    result = []
    can_cancel = _is_manager()
    for order in orders:
        counts = {"New": 0.0, "Accepted": 0.0, "Preparing": 0.0, "Ready": 0.0, "Served": 0.0, "Cancelled": 0.0}
        details = []
        for row in items_by_order.get(order.name, []):
            status = row.custom_preparation_status or "New"
            if status not in counts:
                status = "New"
            qty = float(row.qty or 0)
            counts[status] += qty
            details.append(
                {
                    "row_name": row.name,
                    "item_code": row.item_code,
                    "item_name": row.item_name or row.item_code,
                    "qty": qty,
                    "uom": row.uom,
                    "kitchen_counter": row.custom_kitchen_counter,
                    "kitchen_note": row.custom_kitchen_note,
                    "status": status,
                    "ready_at": row.custom_ready_at,
                    "served_at": row.custom_served_at,
                    "can_cancel": can_cancel and status == "New",
                }
            )

        active_qty = sum(counts[key] for key in ("New", "Accepted", "Preparing", "Ready", "Served"))
        result.append(
            {
                "name": order.name,
                "session": order.custom_restaurant_session,
                "customer": order.customer,
                "customer_name": order.customer_name or order.customer,
                "creation": order.creation,
                "grand_total": float(order.grand_total or 0),
                "total_qty": active_qty + counts["Cancelled"],
                "active_qty": active_qty,
                "new_qty": counts["New"],
                "preparing_qty": counts["Accepted"] + counts["Preparing"],
                "ready_qty": counts["Ready"],
                "served_qty": counts["Served"],
                "cancelled_qty": counts["Cancelled"],
                "fully_served": active_qty > 0 and counts["Served"] >= active_qty,
                "preparation_summary": order.custom_preparation_summary or "New",
                "items": details,
            }
        )
    return {"orders": result, "count": len(result), "user": frappe.session.user}


@frappe.whitelist()
def get_ready_orders():
    require_any_role("Waiter")
    order_names = _active_order_names()
    if not order_names:
        return {"orders": [], "count": 0, "item_count": 0, "user": frappe.session.user}

    ready_rows = frappe.get_all(
        "Sales Order Item",
        filters={
            "parent": ["in", order_names],
            "parenttype": "Sales Order",
            "docstatus": 1,
            "custom_preparation_status": "Ready",
        },
        fields=[
            "name", "parent", "idx", "item_code", "item_name", "qty", "uom", "warehouse",
            "custom_kitchen_counter", "custom_kitchen_note", "custom_ready_at",
        ],
        order_by="parent asc, idx asc",
        limit_page_length=1000,
    )
    parents = list(dict.fromkeys(row.parent for row in ready_rows))
    if not parents:
        return {"orders": [], "count": 0, "item_count": 0, "user": frappe.session.user}

    headers = {
        row.name: row
        for row in frappe.get_all(
            "Sales Order",
            filters={"name": ["in", parents], "docstatus": 1},
            fields=["name", "customer", "creation", "custom_preparation_summary", "custom_restaurant_session"],
            order_by="creation asc",
            limit_page_length=1000,
        )
    }
    status_rows = frappe.get_all(
        "Sales Order Item",
        filters={"parent": ["in", parents], "parenttype": "Sales Order", "docstatus": 1},
        fields=["parent", "custom_preparation_status"],
        order_by="parent asc, idx asc",
        limit_page_length=5000,
    )
    statuses: dict[str, list[str]] = {}
    for row in status_rows:
        statuses.setdefault(row.parent, []).append(row.custom_preparation_status or "New")

    grouped: dict[str, dict] = {}
    for row in ready_rows:
        header = headers.get(row.parent)
        if not header:
            continue
        group = grouped.setdefault(
            row.parent,
            {
                "name": header.name,
                "session": header.custom_restaurant_session,
                "customer": header.customer,
                "creation": header.creation,
                "preparation_summary": header.custom_preparation_summary or "New",
                "can_serve_whole": can_serve_whole(statuses.get(row.parent, [])),
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
                "kitchen_note": row.custom_kitchen_note,
                "ready_at": row.custom_ready_at,
            }
        )

    orders = [grouped[name] for name in parents if name in grouped]
    return {"orders": orders, "count": len(orders), "item_count": len(ready_rows), "user": frappe.session.user}


@frappe.whitelist(methods=["POST"])
def item_action(item_row_name: str, action: str):
    require_any_role("Waiter", "Restaurant Manager")
    if action not in {"Mark Served", "Cancel"}:
        frappe.throw("Invalid waiter action")
    if action == "Cancel" and not _is_manager():
        frappe.throw("Waiters cannot cancel restaurant orders", frappe.PermissionError)

    row = frappe.get_doc("Sales Order Item", item_row_name)
    if row.parenttype != "Sales Order":
        frappe.throw("Invalid Sales Order Item")
    order = frappe.get_doc("Sales Order", row.parent)
    assert_active_restaurant_order(order, waiter=_current_waiter_filter())
    current_status = row.custom_preparation_status or "New"

    if action == "Mark Served":
        if current_status != "Ready":
            frappe.throw("This item is no longer ready to serve")
        frappe.db.set_value(
            "Sales Order Item",
            row.name,
            {
                "custom_preparation_status": "Served",
                "custom_served_at": now_datetime(),
                "custom_prepared_qty": row.qty,
            },
            update_modified=True,
        )
    else:
        if current_status != "New":
            frappe.throw("Only a New item can be cancelled by a waiter")
        _assert_not_billed_or_delivered(row)
        frappe.db.set_value(
            "Sales Order Item",
            row.name,
            {"custom_preparation_status": "Cancelled", "custom_prepared_qty": 0},
            update_modified=True,
        )

    summary = recalculate_sales_order(order.name)
    if action == "Cancel" and summary["active_total"] == 0:
        _cancel_empty_order(order)
        return {"sales_order": order.name, "row_name": row.name, "status": "Cancelled", "order_cancelled": True}

    return {
        "sales_order": order.name,
        "row_name": row.name,
        "status": "Served" if action == "Mark Served" else "Cancelled",
        "preparation_summary": summary["summary"],
        "order_cancelled": False,
    }


@frappe.whitelist(methods=["POST"])
def serve_whole_order(order_name: str):
    require_any_role("Waiter")
    order = frappe.get_doc("Sales Order", order_name)
    assert_active_restaurant_order(order, waiter=_current_waiter_filter())
    rows = frappe.get_all(
        "Sales Order Item",
        filters={"parent": order.name, "parenttype": "Sales Order", "docstatus": 1},
        fields=["name", "qty", "custom_preparation_status"],
        order_by="idx asc",
        limit_page_length=1000,
    )
    statuses = [row.custom_preparation_status or "New" for row in rows]
    if not can_serve_whole(statuses):
        frappe.throw("This Sales Order cannot be served yet because some active items are not Ready")

    served_at = now_datetime()
    served_rows = []
    for row in rows:
        if (row.custom_preparation_status or "New") == "Ready":
            frappe.db.set_value(
                "Sales Order Item",
                row.name,
                {
                    "custom_preparation_status": "Served",
                    "custom_served_at": served_at,
                    "custom_prepared_qty": row.qty,
                },
                update_modified=True,
            )
            served_rows.append(row.name)

    summary = recalculate_sales_order(order.name)
    return {
        "sales_order": order.name,
        "served_rows": served_rows,
        "preparation_summary": summary["summary"],
    }


def _assert_not_billed_or_delivered(row) -> None:
    invoice = frappe.db.get_value("Sales Invoice Item", {"so_detail": row.name, "docstatus": 1}, "parent")
    if invoice:
        frappe.throw(f"This item is already billed on Sales Invoice {invoice}")
    delivery = frappe.db.get_value("Delivery Note Item", {"so_detail": row.name, "docstatus": 1}, "parent")
    if delivery:
        frappe.throw(f"This item is already delivered on Delivery Note {delivery}")


def _cancel_empty_order(order) -> None:
    invoice = frappe.db.get_value("Sales Invoice Item", {"sales_order": order.name, "docstatus": 1}, "parent")
    delivery = frappe.db.get_value("Delivery Note Item", {"against_sales_order": order.name, "docstatus": 1}, "parent")
    if invoice or delivery:
        frappe.throw("All items are cancelled, but submitted billing or delivery already exists")

    draft_rows = frappe.get_all(
        "Sales Invoice Item",
        filters={"sales_order": order.name, "docstatus": 0},
        pluck="parent",
        limit_page_length=100,
    )
    for invoice_name in dict.fromkeys(draft_rows):
        frappe.delete_doc("Sales Invoice", invoice_name, ignore_permissions=True)
    order.reload()
    order.cancel()
