# Server Script API: bcn_waiter_order_progress
# Deployment target: https://ourcity.s.frappe.cloud
#
# Current Server-Script-only restaurant flow:
# - waiter orders are Open Draft Sales Orders
# - Draft Billing orders stay visible so waiter can re-request an updated bill
# - this endpoint reads the same active-order state used by the table screen

COMPANY = "Doh Myot Taw BBQ & Restaurant"

profile = frappe.get_doc("POS Profile", "DMT")
COMPANY = (profile.company or "").strip()
if not COMPANY:
    frappe.throw("POS Profile DMT must have a Company.")

current_user = frappe.session.user
if not current_user or current_user == "Guest":
    frappe.throw("Authentication is required.")

role_rows = frappe.get_all(
    "Has Role",
    filters={
        "parent": current_user,
        "parenttype": "User",
    },
    fields=["role"],
    limit_page_length=200,
)

roles = []
for role_row in role_rows:
    if role_row.role and role_row.role not in roles:
        roles.append(role_row.role)

allowed_user = (
    current_user == "Administrator"
    or "Admin" in roles
    or "System Manager" in roles
    or "Waiter" in roles
    or "Restaurant Manager" in roles
)

if not allowed_user:
    frappe.throw("You are not allowed to view restaurant order progress.")

orders = frappe.get_all(
    "Sales Order",
    filters={
        "company": COMPANY,
        "docstatus": 0,
        "custom_restaurant_status": ["in", ["Open", "Billing"]],
    },
    fields=[
        "name",
        "customer",
        "customer_name",
        "creation",
        "grand_total",
        "net_total",
        "total_taxes_and_charges",
        "currency",
        "custom_restaurant_status",
    ],
    order_by="creation asc",
    limit_page_length=500,
)

result = []
for order in orders:
    item_rows = frappe.get_all(
        "Sales Order Item",
        filters={
            "parent": order.name,
            "parenttype": "Sales Order",
            "docstatus": 0,
        },
        fields=[
            "name",
            "idx",
            "item_code",
            "item_name",
            "qty",
            "uom",
            "rate",
            "amount",
            "custom_kitchen_counter",
            "custom_kitchen_note",
            "custom_foc",
            "custom_parcel",
            "custom_printed_qty",
        ],
        order_by="idx asc",
        limit_page_length=1000,
    )

    # Live room-charge preview is computed in memory, never saved to the SO.
    # It uses the same 1-hour minimum / 30-minute rounding as StartCheckout.
    preview_doc = None
    room_preview = None
    room_codes = []
    has_room_flag = frappe.get_meta("Item").has_field("custom_is_room_charge")
    for row in item_rows:
        item_group = frappe.db.get_value("Item", row.item_code, "item_group") or ""
        flag = (
            frappe.db.get_value("Item", row.item_code, "custom_is_room_charge")
            if has_room_flag else False
        )
        if flag or item_group.strip().lower() == "room charges":
            room_codes.append(row.item_code)
    if len(room_codes) > 1:
        frappe.throw("Only one Room Charges item is allowed per Sales Order")
    if room_codes:
        preview_doc = frappe.get_doc("Sales Order", order.name)
        room_line = None
        for item in preview_doc.items:
            if item.item_code == room_codes[0]:
                room_line = item
                break
        if room_line and room_line.uom != "Hour":
            frappe.throw("Room Charges UOM must be Hour")
        check_in = frappe.utils.get_datetime(
            preview_doc.get("custom_check_in") or preview_doc.creation
        )
        check_out = preview_doc.get("custom_check_out")
        effective_end = (
            frappe.utils.get_datetime(check_out)
            if check_out else frappe.utils.now_datetime()
        )
        elapsed = max(0, (effective_end - check_in).total_seconds())
        half_hours = max(2, int((elapsed + 1799.999999) // 1800))
        billable = half_hours / 2.0
        if room_line:
            if order.custom_restaurant_status == "Open" and not check_out:
                room_line.qty = billable
                preview_doc.calculate_taxes_and_totals()
            else:
                billable = frappe.utils.flt(room_line.qty)
            room_preview = {
                "check_in": str(check_in),
                "check_out": str(check_out) if check_out else None,
                "elapsed_seconds": float(elapsed),
                "billable_hours": float(billable),
                "hourly_rate": float(room_line.rate or 0),
                "amount": float(room_line.amount or 0),
                "is_live": bool(
                    order.custom_restaurant_status == "Open" and not check_out
                ),
            }

    item_snapshot = {}
    if preview_doc and room_preview:
        item_snapshot = {item.name: item for item in preview_doc.items}

    details = []
    total_qty = 0.0
    for row in item_rows:
        snap = item_snapshot.get(row.name, row)
        qty = frappe.utils.flt(snap.qty)
        total_qty = total_qty + qty
        details.append(
            {
                "row_name": row.name,
                "item_code": row.item_code,
                "item_name": row.item_name or row.item_code,
                "qty": float(qty),
                "uom": row.uom,
                "rate": float(snap.rate or 0),
                "amount": float(snap.amount or 0),
                "kitchen_counter": row.custom_kitchen_counter,
                "kitchen_note": row.custom_kitchen_note,
                "custom_foc": int(row.custom_foc or 0),
                "custom_parcel": int(row.custom_parcel or 0),
                "status": "New",
                "printed_qty": float(row.custom_printed_qty or 0),
                # All active quantity can be cancelled, even if previously
                # printed. Keep at least one unit when this is the final row.
                "cancelable_qty": float(
                    max(0, qty if len(item_rows) > 1 else qty - 1)
                ),
                "can_cancel": (
                    order.custom_restaurant_status == "Open"
                    and (len(item_rows) > 1 or qty >= 2)
                ),
            }
        )

    tax_data = frappe.get_all(
        "Sales Taxes and Charges",
        filters={"parent": order.name, "parenttype": "Sales Order"},
        fields=["account_head", "description", "tax_amount"],
        limit_page_length=100,
    )
    tax_details = []
    if preview_doc and room_preview:
        tax_data = preview_doc.taxes
    for tax in tax_data:
        amount = float(tax.tax_amount or 0)
        if abs(amount) <= 0.00001:
            continue
        account = (tax.account_head or "").lower()
        desc = (tax.description or "").lower()
        if "service charg" in account or "service charg" in desc:
            label = "Service Charges"
        elif "commercial tax" in account or "vat" in account or "commercial tax" in desc:
            label = "Commercial Tax"
        else:
            label = tax.description or tax.account_head or "Tax"
        tax_details.append({"label": label, "amount": amount})

    result.append(
        {
            "name": order.name,
            "customer": order.customer,
            "customer_name": order.customer_name or order.customer,
            "creation": order.creation,
            "grand_total": float(
                preview_doc.grand_total if room_preview else order.grand_total or 0
            ),
            "net_total": float(
                preview_doc.net_total if room_preview else order.net_total or 0
            ),
            "total_taxes_and_charges": float(
                preview_doc.total_taxes_and_charges if room_preview else order.total_taxes_and_charges or 0
            ),
            "room_preview": room_preview,
            "currency": order.currency or "MMK",
            "taxes": tax_details,
            "total_qty": float(total_qty),
            "active_qty": float(total_qty),
            "new_qty": float(total_qty),
            "preparing_qty": 0.0,
            "ready_qty": 0.0,
            "served_qty": 0.0,
            "cancelled_qty": 0.0,
            "fully_served": False,
            "preparation_summary": "New",
            "items": details,
        }
    )

frappe.response["message"] = {
    "orders": result,
    "count": len(result),
    "user": current_user,
}
