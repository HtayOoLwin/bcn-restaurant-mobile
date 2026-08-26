import frappe
from frappe.custom.doctype.custom_field.custom_field import create_custom_fields


DEFAULT_SETTINGS = {
    "company": "BCN Restaurant",
    "pos_profile": "BCN Restaurant POS",
    "selling_price_list": "Restaurant Menu Price",
    "default_currency": "MMK",
    "dine_in_customer_group": "Dine In",
    "takeaway_customer_group": "Takeaway",
}


def before_install():
    required_fields = {
        "Item": ["custom_kitchen_counter"],
        "Sales Order": [
            "custom_preparation_summary",
            "custom_ready_count",
            "custom_total_prep_lines",
        ],
        "Sales Order Item": [
            "custom_kitchen_counter",
            "custom_preparation_status",
            "custom_prepared_qty",
            "custom_kitchen_note",
            "custom_ready_at",
            "custom_served_at",
        ],
    }

    if not frappe.db.exists("DocType", "Kitchen Counter"):
        frappe.throw(
            "Kitchen Counter DocType is required. Install this app on the existing BCN Restaurant site "
            "or migrate the current restaurant customizations first."
        )

    missing = []
    for doctype, fieldnames in required_fields.items():
        meta = frappe.get_meta(doctype)
        for fieldname in fieldnames:
            if not meta.has_field(fieldname):
                missing.append(f"{doctype}.{fieldname}")

    if missing:
        frappe.throw(
            "Required BCN Restaurant custom fields are missing: " + ", ".join(missing)
        )


def create_sales_order_custom_fields():
    create_custom_fields(
        {
            "Sales Order": [
                {
                    "fieldname": "custom_restaurant_session",
                    "label": "Restaurant Session",
                    "fieldtype": "Link",
                    "options": "Restaurant Table Session",
                    "insert_after": "customer",
                    "read_only": 1,
                    "no_copy": 1,
                },
                {
                    "fieldname": "custom_client_order_id",
                    "label": "Client Order ID",
                    "fieldtype": "Data",
                    "insert_after": "custom_restaurant_session",
                    "read_only": 1,
                    "no_copy": 1,
                    "unique": 1,
                },
            ]
        },
        update=True,
    )


def initialize_restaurant_settings():
    for fieldname, value in DEFAULT_SETTINGS.items():
        if not frappe.db.get_single_value("Restaurant Settings", fieldname):
            frappe.db.set_single_value("Restaurant Settings", fieldname, value)


def after_install():
    create_sales_order_custom_fields()
    initialize_restaurant_settings()
    frappe.db.commit()
