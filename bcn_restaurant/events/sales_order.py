from __future__ import annotations

import frappe


def route_kitchen_items(doc, method=None):
    active_lines = 0
    ready_lines = 0

    for row in doc.items:
        item = frappe.get_cached_doc("Item", row.item_code)
        counter_name = row.custom_kitchen_counter or item.custom_kitchen_counter
        if not counter_name:
            frappe.throw(f"Kitchen Counter is required for restaurant item {row.item_code}")

        counter = frappe.get_cached_doc("Kitchen Counter", counter_name)
        if not counter.enabled:
            frappe.throw(f"Kitchen Counter {counter_name} is disabled")
        if not counter.warehouse:
            frappe.throw(f"Kitchen Counter {counter_name} has no Warehouse")

        row.custom_kitchen_counter = counter_name
        row.warehouse = counter.warehouse
        if not row.custom_preparation_status:
            row.custom_preparation_status = "New"

        if row.custom_preparation_status != "Cancelled":
            active_lines += 1
        if row.custom_preparation_status in {"Ready", "Served"}:
            ready_lines += 1

    if hasattr(doc, "custom_total_prep_lines"):
        doc.custom_total_prep_lines = active_lines
    if hasattr(doc, "custom_ready_count"):
        doc.custom_ready_count = ready_lines
    if hasattr(doc, "custom_preparation_summary") and active_lines and not doc.custom_preparation_summary:
        doc.custom_preparation_summary = "New"
