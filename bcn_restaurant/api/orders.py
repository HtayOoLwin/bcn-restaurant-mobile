from __future__ import annotations

import frappe
from frappe.utils import nowdate

from bcn_restaurant.api.common import current_roles, get_settings, require_any_role
from bcn_restaurant.domain.order_payload import normalize_items, validate_client_order_id
from bcn_restaurant.domain.session_access import can_use_session
from bcn_restaurant.services.menu import get_active_item_price


@frappe.whitelist(methods=["POST"])
def create_order(
    customer: str,
    items,
    client_order_id: str,
    session: str | None = None,
    remarks: str | None = None,
    guest_count: int | str | None = None,
):
    require_any_role("Waiter")
    settings = get_settings()
    client_order_id = validate_client_order_id(client_order_id)
    normalized_items = normalize_items(items)

    existing = frappe.db.get_value(
        "Sales Order",
        {"custom_client_order_id": client_order_id, "docstatus": ["!=", 2]},
        ["name", "custom_restaurant_session", "grand_total", "custom_preparation_summary"],
        as_dict=True,
    )
    if existing:
        return _order_response(existing, duplicate=True)

    customer = (customer or "").strip()
    customer_row = frappe.db.get_value(
        "Customer",
        customer,
        ["name", "customer_group", "disabled"],
        as_dict=True,
    )
    if not customer_row or customer_row.disabled:
        frappe.throw("Customer / table is invalid or disabled")

    allowed_groups = {settings["dine_in_customer_group"], settings["takeaway_customer_group"]}
    if customer_row.customer_group not in allowed_groups:
        frappe.throw("Customer is not a configured restaurant table/takeaway customer")

    session_name = _get_or_create_session(
        customer=customer,
        customer_group=customer_row.customer_group,
        session=session,
        guest_count=guest_count,
    )

    doc = frappe.new_doc("Sales Order")
    doc.company = settings["company"]
    doc.customer = customer
    doc.transaction_date = nowdate()
    doc.selling_price_list = settings["selling_price_list"]
    doc.currency = settings["default_currency"]
    doc.price_list_currency = settings["default_currency"]
    doc.conversion_rate = 1
    doc.plc_conversion_rate = 1
    doc.custom_restaurant_session = session_name
    doc.custom_client_order_id = client_order_id
    doc.remarks = (remarks or "").strip() or None

    for payload_row in normalized_items:
        item = _validate_menu_item(payload_row["item_code"])
        uom = payload_row.get("uom") or item.stock_uom
        if uom != item.stock_uom:
            frappe.throw(
                f"Phase 1 ordering requires Stock UOM {item.stock_uom} for item {item.name}"
            )

        rate = get_active_item_price(
            item_code=item.name,
            price_list=settings["selling_price_list"],
            uom=uom,
        )

        row = doc.append(
            "items",
            {
                "item_code": item.name,
                "qty": payload_row["qty"],
                "uom": uom,
                "stock_uom": item.stock_uom,
                "conversion_factor": 1,
                "rate": rate,
                "delivery_date": nowdate(),
            },
        )
        if payload_row.get("kitchen_note"):
            row.custom_kitchen_note = payload_row["kitchen_note"]

    try:
        doc.insert()
        doc.submit()
    except frappe.UniqueValidationError:
        existing = frappe.db.get_value(
            "Sales Order",
            {"custom_client_order_id": client_order_id, "docstatus": ["!=", 2]},
            ["name", "custom_restaurant_session", "grand_total", "custom_preparation_summary"],
            as_dict=True,
        )
        if existing:
            return _order_response(existing, duplicate=True)
        raise

    return _order_response(doc, duplicate=False)


def _validate_menu_item(item_code: str):
    item = frappe.get_cached_doc("Item", item_code)
    if item.disabled or not item.is_sales_item:
        frappe.throw(f"Item {item_code} is not available for sale")
    if not item.custom_kitchen_counter:
        frappe.throw(f"Item {item_code} has no Kitchen Counter")
    return item


def _get_or_create_session(
    customer: str,
    customer_group: str,
    session: str | None,
    guest_count: int | str | None,
) -> str:
    if session:
        doc = frappe.get_doc("Restaurant Table Session", session)
        if doc.customer != customer:
            frappe.throw("Restaurant session does not belong to this customer/table")
        if doc.status != "Open":
            frappe.throw("Restaurant session is not open")
        if not can_use_session(doc.waiter, frappe.session.user, current_roles()):
            frappe.throw("Restaurant session belongs to another waiter", frappe.PermissionError)
        return doc.name

    existing = frappe.db.get_value(
        "Restaurant Table Session",
        {"customer": customer, "status": "Open"},
        "name",
        order_by="opened_at desc",
    )
    if existing:
        existing_doc = frappe.get_doc("Restaurant Table Session", existing)
        if not can_use_session(existing_doc.waiter, frappe.session.user, current_roles()):
            frappe.throw("Restaurant session belongs to another waiter", frappe.PermissionError)
        return existing

    try:
        guests = int(guest_count or 1)
    except (TypeError, ValueError):
        frappe.throw("guest_count must be a whole number")
    if guests < 1:
        frappe.throw("guest_count must be at least 1")

    doc = frappe.get_doc(
        {
            "doctype": "Restaurant Table Session",
            "customer": customer,
            "customer_group": customer_group,
            "waiter": frappe.session.user,
            "guest_count": guests,
            "status": "Open",
        }
    )
    doc.insert()
    return doc.name


def _order_response(doc, duplicate: bool):
    if isinstance(doc, dict):
        name = doc.get("name")
        session_name = doc.get("custom_restaurant_session")
        grand_total = doc.get("grand_total")
        preparation_summary = doc.get("custom_preparation_summary")
    else:
        name = doc.name
        session_name = doc.custom_restaurant_session
        grand_total = doc.grand_total
        preparation_summary = doc.custom_preparation_summary

    return {
        "sales_order": name,
        "session": session_name,
        "grand_total": float(grand_total or 0),
        "preparation_summary": preparation_summary or "New",
        "duplicate": duplicate,
    }
