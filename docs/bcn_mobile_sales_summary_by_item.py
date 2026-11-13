# Server Script API: bcn_mobile_sales_summary_by_item
# Script Type: API | Allow Guest: No
# Company: Doh Myoh Taw BBQ & Restaurant
# Summary grouping: Item Code + Item Group, over the requested date range
#
# Qty includes FOC. FOC Qty is a subset, not added to Qty again.
# This script identifies FOC from item-level explicit flags; zero price alone
# is NOT treated as FOC. Verify the actual OurCity FOC field against the
# existing bcn_cashier_billing ItemSalesReport implementation before production.

COMPANY = "Doh Myoh Taw BBQ & Restaurant"
CURRENCY = "MMK"

user = frappe.session.user
if not user or user == "Guest":
    frappe.throw("Authentication required")

role_rows = frappe.get_all(
    "Has Role",
    filters={"parent": user, "parenttype": "User"},
    fields=["role"],
    limit_page_length=100
)
roles = [row.role for row in role_rows]
if user != "Administrator" and not (
    "System Manager" in roles
    or "Restaurant Manager" in roles
    or "Cashier" in roles
):
    frappe.throw("Not allowed to view cashier sales summary")

from_date = frappe.form_dict.get("from_date") or frappe.utils.today()
to_date = frappe.form_dict.get("to_date") or from_date
options = frappe.form_dict.get("options") or "All"
selected_counter = (frappe.form_dict.get("sales_counter") or "").strip()

if options not in ("All", "Sales", "Return"):
    frappe.throw("Options must be All, Sales or Return")

if frappe.utils.getdate(from_date) > frappe.utils.getdate(to_date):
    frappe.throw("From Date must be before or equal to To Date")

if not frappe.get_meta("Item Group").has_field("custom_oc_counter"):
    frappe.throw("Item Group.custom_oc_counter does not exist")

# Submitted invoice headers only
header_filters = {
    "company": COMPANY,
    "docstatus": 1,
    "posting_date": ["between", [from_date, to_date]]
}
if options == "Sales":
    header_filters["is_return"] = 0
elif options == "Return":
    header_filters["is_return"] = 1

invoice_names = []
invoices = frappe.get_list(
    "Sales Invoice",
    filters=header_filters,
    fields=["name"],
    limit_page_length=0
)
for inv in invoices:
    invoice_names.append(inv.name)

# Explicit FOC flags: check fields exist before selecting.
si_meta = frappe.get_meta("Sales Invoice Item")
so_meta = frappe.get_meta("Sales Order Item")
si_foc_fields = []
so_foc_fields = []
for field in ("is_free_item", "custom_is_foc", "custom_foc", "custom_oc_is_foc"):
    if si_meta.has_field(field):
        si_foc_fields.append(field)
    if so_meta.has_field(field):
        so_foc_fields.append(field)

invoice_items = []
for start in range(0, len(invoice_names), 200):
    batch = invoice_names[start:start + 200]
    fields = [
        "name", "parent", "item_code", "item_name",
        "item_group", "qty", "amount", "so_detail"
    ]
    for field in si_foc_fields:
        if field not in fields:
            fields.append(field)

    rows = frappe.get_all(
        "Sales Invoice Item",
        filters={
            "parent": ["in", batch],
            "parenttype": "Sales Invoice",
            "parentfield": "items"
        },
        fields=fields,
        limit_page_length=0
    )
    for row in rows:
        invoice_items.append(row)

so_names = []
group_names = []
for item in invoice_items:
    if item.so_detail and item.so_detail not in so_names:
        so_names.append(item.so_detail)
    if item.item_group and item.item_group not in group_names:
        group_names.append(item.item_group)

# Look up linked Sales Order Item flags
so_foc_map = {}
if so_foc_fields:
    for start in range(0, len(so_names), 200):
        batch = so_names[start:start + 200]
        so_fields = ["name"]
        for field in so_foc_fields:
            so_fields.append(field)
        rows = frappe.get_all(
            "Sales Order Item",
            filters={"name": ["in", batch]},
            fields=so_fields,
            limit_page_length=0
        )
        for row in rows:
            is_foc = False
            for field in so_foc_fields:
                if row.get(field):
                    is_foc = True
            so_foc_map[row.name] = is_foc

counter_map = {}
for start in range(0, len(group_names), 200):
    batch = group_names[start:start + 200]
    groups = frappe.get_all(
        "Item Group",
        filters={"name": ["in", batch]},
        fields=["name", "custom_oc_counter"],
        limit_page_length=0
    )
    for group in groups:
        counter_map[group.name] = (
            str(group.get("custom_oc_counter") or "").strip() or "-"
        )

summary = {}
counter_names = []
for item in invoice_items:
    counter = counter_map.get(item.item_group, "-")
    if counter not in counter_names:
        counter_names.append(counter)

    if selected_counter and counter != selected_counter:
        continue

    code = item.item_code or ""
    group = item.item_group or ""
    key = (code, group)
    if key not in summary:
        summary[key] = {
            "item_code": code,
            "item_name": item.item_name or code,
            "item_group": group,
            "qty": 0.0,
            "foc_qty": 0.0,
            "amount": 0.0
        }

    foc = False
    for field in si_foc_fields:
        if item.get(field):
            foc = True
    if item.so_detail and so_foc_map.get(item.so_detail):
        foc = True

    qty = frappe.utils.flt(item.qty, 2)
    amount = frappe.utils.flt(item.amount, 2)
    result = summary[key]
    result["qty"] = frappe.utils.flt(result["qty"] + qty, 2)
    result["amount"] = frappe.utils.flt(result["amount"] + amount, 2)
    if foc:
        result["foc_qty"] = frappe.utils.flt(result["foc_qty"] + qty, 2)

rows = []
for key in sorted(summary.keys()):
    rows.append(summary[key])

total_qty = 0.0
total_foc_qty = 0.0
total_amount = 0.0
for row in rows:
    total_qty = total_qty + row["qty"]
    total_foc_qty = total_foc_qty + row["foc_qty"]
    total_amount = total_amount + row["amount"]

counter_names.sort()

frappe.response["message"] = {
    "success": True,
    "company": COMPANY,
    "currency": CURRENCY,
    "from_date": str(from_date),
    "to_date": str(to_date),
    "options": options,
    "sales_counter": selected_counter,
    "counters": counter_names,
    "rows": rows,
    "total_qty": frappe.utils.flt(total_qty, 2),
    "total_foc_qty": frappe.utils.flt(total_foc_qty, 2),
    "total_amount": frappe.utils.flt(total_amount, 2),
    "foc_detection_available": bool(si_foc_fields or so_foc_fields)
}
