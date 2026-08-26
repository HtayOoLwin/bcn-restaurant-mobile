from __future__ import annotations

import frappe

from bcn_restaurant.domain.roles import build_role_flags


REQUIRED_SETTING_FIELDS = (
    "company",
    "pos_profile",
    "selling_price_list",
    "default_currency",
    "dine_in_customer_group",
    "takeaway_customer_group",
)


def get_settings() -> dict[str, str]:
    doc = frappe.get_single("Restaurant Settings")
    result = {fieldname: getattr(doc, fieldname, None) for fieldname in REQUIRED_SETTING_FIELDS}
    missing = [fieldname for fieldname, value in result.items() if not value]
    if missing:
        frappe.throw(f"Restaurant Settings is incomplete: {', '.join(missing)}")
    return result


def current_roles() -> list[str]:
    user = frappe.session.user
    if user == "Administrator":
        return ["Administrator"]
    return frappe.get_roles(user)


def require_any_role(*roles: str) -> None:
    user_roles = set(current_roles())
    if "Administrator" in user_roles or "System Manager" in user_roles:
        return
    if not user_roles.intersection(roles):
        frappe.throw("You are not permitted to use this restaurant action", frappe.PermissionError)


def role_flags() -> dict[str, bool]:
    return build_role_flags(current_roles())


def get_user_kitchen_counters() -> list[str]:
    if frappe.session.user == "Administrator" or "System Manager" in set(current_roles()):
        return frappe.get_all(
            "Kitchen Counter",
            filters={"enabled": 1},
            pluck="name",
            order_by="sequence asc, name asc",
        )

    return frappe.get_all(
        "User Permission",
        filters={
            "user": frappe.session.user,
            "allow": "Kitchen Counter",
            "apply_to_all_doctypes": 1,
        },
        pluck="for_value",
        order_by="for_value asc",
    )
