from __future__ import annotations

import frappe

from bcn_restaurant.api.common import current_roles, get_settings, role_flags


@frappe.whitelist()
def get_bootstrap():
    if frappe.session.user == "Guest":
        frappe.throw("Login required", frappe.AuthenticationError)

    settings = get_settings()
    user = frappe.get_cached_doc("User", frappe.session.user)
    roles = current_roles()

    return {
        "user": frappe.session.user,
        "full_name": user.full_name,
        "roles": roles,
        "permissions": role_flags(),
        "company": settings["company"],
        "currency": settings["default_currency"],
        "selling_price_list": settings["selling_price_list"],
    }
