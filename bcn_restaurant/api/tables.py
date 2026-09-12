from __future__ import annotations

import frappe

from bcn_restaurant.api.common import get_settings, require_any_role


def _available_customer_groups() -> list[str]:
    leaf_group_rows = frappe.get_all(
        "Customer Group",
        filters={"is_group": 0},
        fields=["name"],
        order_by="name asc",
        limit_page_length=500,
    )
    enabled_customer_rows = frappe.get_all(
        "Customer",
        filters={"disabled": 0},
        fields=["customer_group"],
        limit_page_length=5000,
    )

    groups_with_customers = {
        row.customer_group for row in enabled_customer_rows if row.customer_group
    }
    return [
        row.name for row in leaf_group_rows if row.name in groups_with_customers
    ]


def _resolve_customer_group(
    customer_groups: list[str],
    customer_group: str | None,
    service_type: str | None,
) -> str:
    requested = (customer_group or "").strip()
    if requested:
        if requested not in customer_groups:
            frappe.throw(
                "Selected Customer Group is not available for restaurant tables."
            )
        return requested

    settings = get_settings()
    legacy = (service_type or "").strip().lower()
    if legacy in ("dine_in", "dinein"):
        preferred = settings["dine_in_customer_group"]
    elif legacy == "takeaway":
        preferred = settings["takeaway_customer_group"]
    else:
        preferred = settings["dine_in_customer_group"]

    if preferred in customer_groups:
        return preferred
    return customer_groups[0] if customer_groups else ""


@frappe.whitelist()
def get_tables(
    customer_group: str | None = None,
    service_type: str | None = None,
):
    require_any_role("Waiter")

    customer_groups = _available_customer_groups()
    customer_group = _resolve_customer_group(
        customer_groups,
        customer_group,
        service_type,
    )

    customers = []
    if customer_group:
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

    resolved_service_type = "customer_group"
    settings = get_settings()
    if customer_group == settings["dine_in_customer_group"]:
        resolved_service_type = "dine_in"
    elif customer_group == settings["takeaway_customer_group"]:
        resolved_service_type = "takeaway"

    return {
        "service_type": resolved_service_type,
        "customer_group": customer_group,
        "customer_groups": customer_groups,
        "tables": result,
    }
