from __future__ import annotations

import frappe

from bcn_restaurant.api.common import get_settings
from bcn_restaurant.domain.preparation import summarize_statuses

ACTIVE_SESSION_STATUSES = ("Open", "Billing")


def get_active_session_order_names(waiter: str | None = None) -> list[str]:
    settings = get_settings()
    session_filters: dict = {"status": ["in", list(ACTIVE_SESSION_STATUSES)]}
    if waiter:
        session_filters["waiter"] = waiter

    session_names = frappe.get_all(
        "Restaurant Table Session",
        filters=session_filters,
        pluck="name",
        order_by="opened_at asc",
    )
    if not session_names:
        return []

    return frappe.get_all(
        "Sales Order",
        filters={
            "company": settings["company"],
            "docstatus": 1,
            "custom_restaurant_session": ["in", session_names],
        },
        pluck="name",
        order_by="creation asc",
    )


def assert_active_restaurant_order(order_doc, waiter: str | None = None):
    settings = get_settings()
    if order_doc.doctype != "Sales Order" or order_doc.company != settings["company"] or order_doc.docstatus != 1:
        frappe.throw("Only submitted restaurant Sales Orders can be updated")

    session_name = getattr(order_doc, "custom_restaurant_session", None)
    if not session_name:
        frappe.throw("Sales Order is not linked to an active Restaurant Table Session")

    session = frappe.get_doc("Restaurant Table Session", session_name)
    if session.status not in ACTIVE_SESSION_STATUSES:
        frappe.throw("Restaurant Table Session is no longer active")
    if waiter and session.waiter != waiter:
        frappe.throw("This restaurant session belongs to another waiter", frappe.PermissionError)
    return session


def recalculate_sales_order(order_name: str) -> dict:
    rows = frappe.get_all(
        "Sales Order Item",
        filters={"parent": order_name, "parenttype": "Sales Order", "docstatus": 1},
        fields=["custom_preparation_status"],
        order_by="idx asc",
        limit_page_length=1000,
    )
    result = summarize_statuses([row.custom_preparation_status or "New" for row in rows])
    frappe.db.set_value(
        "Sales Order",
        order_name,
        {
            "custom_preparation_summary": result["summary"],
            "custom_ready_count": result["ready_count"],
            "custom_total_prep_lines": result["active_total"],
        },
        update_modified=True,
    )
    return result
