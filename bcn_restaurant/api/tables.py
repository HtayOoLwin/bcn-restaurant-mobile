from __future__ import annotations

import frappe

from bcn_restaurant.api.common import get_settings, require_any_role


SERVICE_TYPE_MAP = {
    "dine_in": "dine_in_customer_group",
    "dinein": "dine_in_customer_group",
    "takeaway": "takeaway_customer_group",
}


@frappe.whitelist()
def get_tables(service_type: str = "dine_in"):
    require_any_role("Waiter")
    settings = get_settings()
    key = SERVICE_TYPE_MAP.get((service_type or "").strip().lower())
    if not key:
        frappe.throw("service_type must be dine_in or takeaway")

    customer_group = settings[key]
    customers = frappe.get_all(
        "Customer",
        filters={"customer_group": customer_group, "disabled": 0},
        fields=["name", "customer_name", "customer_group"],
        order_by="customer_name asc, name asc",
    )

    customer_names = [row.name for row in customers]
    sessions_by_customer = {}
    if customer_names:
        sessions = frappe.get_all(
            "Restaurant Table Session",
            filters={
                "customer": ["in", customer_names],
                "status": ["in", ["Open", "Billing"]],
            },
            fields=["name", "customer", "status", "waiter", "opened_at"],
            order_by="opened_at desc",
        )
        for session in sessions:
            sessions_by_customer.setdefault(session.customer, session)

    result = []
    for row in customers:
        session = sessions_by_customer.get(row.name)
        result.append(
            {
                "customer": row.name,
                "customer_name": row.customer_name,
                "customer_group": row.customer_group,
                "is_open": bool(session),
                "session": session.name if session else None,
                "session_status": session.status if session else None,
                "waiter": session.waiter if session else None,
                "opened_at": session.opened_at if session else None,
            }
        )

    return {
        "service_type": service_type,
        "customer_group": customer_group,
        "tables": result,
    }
