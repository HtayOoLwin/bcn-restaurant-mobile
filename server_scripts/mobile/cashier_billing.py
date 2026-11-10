# Server Script API: bcn_cashier_billing
# Deployment target: https://ourcity.s.frappe.cloud
#
# GET:
# - list Open Draft Sales Orders immediately
# - list submitted Billing Sales Orders that have a Draft Sales Invoice
# - include latest BCN Print Job status and DMT payment modes
#
# POST action=StartCheckout: freeze check-out, room hours and totals once.
# POST action=Pay: prepare the frozen Billing Sales Order and Draft Sales Invoice.
# POST action=ConfirmPayment: complete the selected Cash / Credit tender.
# Duplicate checkout calls keep the original check-out time and room charges.
#
# No manual commit/rollback is used.

POS_PROFILE = "DMT"
CURRENCY = "MMK"
AMOUNT_TOLERANCE = 0.01

# Use the same Company as bcn_mobile_create_order, waiter progress and tables.
# Resolve it before helper definitions so their default COMPANY arguments match.
profile_settings = frappe.get_doc("POS Profile", POS_PROFILE)
COMPANY = (profile_settings.company or "").strip()
if not COMPANY:
    frappe.throw("POS Profile DMT must have a Company.")


def get_mode_details(profile, mode_name, COMPANY=COMPANY, CURRENCY=CURRENCY):
    allowed_modes = []
    for payment in profile.payments:
        allowed_name = (payment.mode_of_payment or "").strip()
        if allowed_name and allowed_name not in allowed_modes:
            allowed_modes.append(allowed_name)

    if mode_name not in allowed_modes:
        frappe.throw("Mode of Payment is not allowed by DMT: " + mode_name)

    mode_row = frappe.db.get_value(
        "Mode of Payment",
        mode_name,
        ["name", "enabled", "type"],
        as_dict=True,
    )
    if not mode_row or not mode_row.enabled:
        frappe.throw("Mode of Payment is disabled or missing: " + mode_name)

    account = frappe.db.get_value(
        "Mode of Payment Account",
        {
            "parent": mode_name,
            "parenttype": "Mode of Payment",
            "company": COMPANY,
        },
        "default_account",
    )
    if not account:
        frappe.throw("Mode of Payment has no company account: " + mode_name)

    account_row = frappe.db.get_value(
        "Account",
        account,
        [
            "name",
            "company",
            "account_currency",
            "account_type",
            "is_group",
            "disabled",
        ],
        as_dict=True,
    )
    if not account_row:
        frappe.throw("Payment account does not exist: " + account)
    if account_row.company != COMPANY or account_row.is_group or account_row.disabled:
        frappe.throw("Mode of Payment has an unusable company account: " + mode_name)

    account_currency = account_row.account_currency or CURRENCY
    if account_currency != CURRENCY:
        frappe.throw("Payment account currency must be MMK: " + account)

    return {
        "mode_of_payment": mode_name,
        "account": account,
        "account_currency": account_currency,
        "account_type": account_row.account_type,
        "is_cash": mode_row.type == "Cash",
    }


def parse_tenders(raw_payments, profile, allow_empty=False, get_mode_details=get_mode_details):
    if isinstance(raw_payments, str):
        rows = json.loads(raw_payments) if raw_payments else []
    elif isinstance(raw_payments, (list, tuple)):
        rows = raw_payments
    else:
        rows = []

    if not rows and not allow_empty:
        frappe.throw("At least one payment is required")

    tenders = []
    for row in rows:
        if not isinstance(row, dict):
            frappe.throw("Each payment row must be an object")

        mode_name = str(row.get("mode_of_payment") or "").strip()
        amount = float(row.get("amount") or 0)

        if amount <= 0:
            continue
        if not mode_name:
            frappe.throw("mode_of_payment is required")

        mode_details = get_mode_details(profile, mode_name)
        mode_details["amount"] = amount
        tenders.append(mode_details)

    if not tenders and not allow_empty:
        frappe.throw("At least one positive payment is required")

    return tenders


def allocate_tenders(tenders, amount_due, AMOUNT_TOLERANCE=AMOUNT_TOLERANCE):
    remaining = float(amount_due or 0)
    if remaining <= AMOUNT_TOLERANCE:
        frappe.throw("Sales Invoice has no payable amount")

    allocations = []
    cash_rows = []

    for tender in tenders:
        if tender["is_cash"]:
            cash_rows.append(tender)
        else:
            tender_amount = float(tender["amount"] or 0)
            if tender_amount - remaining > AMOUNT_TOLERANCE:
                frappe.throw(
                    "Non-cash payment cannot exceed the remaining amount: "
                    + tender["mode_of_payment"]
                )

            allocated = tender_amount
            if allocated > remaining:
                allocated = remaining

            if allocated > AMOUNT_TOLERANCE:
                allocation = dict(tender)
                allocation["allocated_amount"] = allocated
                allocations.append(allocation)
                remaining = remaining - allocated
                if remaining < AMOUNT_TOLERANCE:
                    remaining = 0

    change_amount = 0.0
    for tender in cash_rows:
        tender_amount = float(tender["amount"] or 0)
        allocated = tender_amount
        if allocated > remaining:
            allocated = remaining

        if allocated > AMOUNT_TOLERANCE:
            allocation = dict(tender)
            allocation["allocated_amount"] = allocated
            allocations.append(allocation)
            remaining = remaining - allocated
            if remaining < AMOUNT_TOLERANCE:
                remaining = 0

        change_amount = change_amount + (tender_amount - allocated)

    if remaining > AMOUNT_TOLERANCE:
        frappe.throw("Tender total is insufficient")

    return allocations, change_amount


def get_linked_draft_sales_invoice_names(sales_order_name):
    rows = frappe.get_all(
        "Sales Invoice Item",
        filters={
            "sales_order": sales_order_name,
            "docstatus": 0,
        },
        fields=["parent"],
        order_by="creation asc",
        limit_page_length=100,
    )

    names = []
    for row in rows:
        if row.parent and row.parent not in names:
            invoice_status = frappe.db.get_value(
                "Sales Invoice",
                row.parent,
                "docstatus",
            )
            if invoice_status == 0:
                names.append(row.parent)
    return names


def get_linked_submitted_sales_invoice_names(sales_order_name):
    rows = frappe.get_all(
        "Sales Invoice Item",
        filters={
            "sales_order": sales_order_name,
            "docstatus": 1,
        },
        fields=["parent"],
        order_by="creation asc",
        limit_page_length=100,
    )

    names = []
    for row in rows:
        if row.parent and row.parent not in names:
            invoice_status = frappe.db.get_value(
                "Sales Invoice",
                row.parent,
                "docstatus",
            )
            if invoice_status == 1:
                names.append(row.parent)
    return names


def get_linked_payment_entry_names(sales_invoice_name):
    rows = frappe.get_all(
        "Payment Entry Reference",
        filters={
            "reference_doctype": "Sales Invoice",
            "reference_name": sales_invoice_name,
            "docstatus": 1,
        },
        fields=["parent"],
        order_by="creation asc",
        limit_page_length=500,
    )

    names = []
    for row in rows:
        if row.parent and row.parent not in names:
            payment_status = frappe.db.get_value(
                "Payment Entry",
                row.parent,
                "docstatus",
            )
            if payment_status == 1:
                names.append(row.parent)
    return names


def validate_invoice_totals(sales_invoice, frozen_net, frozen_taxes, frozen_grand, AMOUNT_TOLERANCE=AMOUNT_TOLERANCE):
    if abs(float(sales_invoice.net_total or 0) - frozen_net) > AMOUNT_TOLERANCE:
        frappe.throw("Sales Invoice net total does not match the frozen bill")
    if (
        abs(float(sales_invoice.total_taxes_and_charges or 0) - frozen_taxes)
        > AMOUNT_TOLERANCE
    ):
        frappe.throw("Sales Invoice taxes do not match the frozen bill")
    if abs(float(sales_invoice.grand_total or 0) - frozen_grand) > AMOUNT_TOLERANCE:
        frappe.throw("Sales Invoice grand total does not match the frozen bill")


def make_payment_entry(sales_invoice, allocation, sequence, COMPANY=COMPANY, CURRENCY=CURRENCY, AMOUNT_TOLERANCE=AMOUNT_TOLERANCE):
    outstanding = float(
        frappe.db.get_value(
            "Sales Invoice",
            sales_invoice.name,
            "outstanding_amount",
        )
        or 0
    )
    allocated_amount = float(allocation["allocated_amount"] or 0)

    if allocated_amount <= AMOUNT_TOLERANCE:
        frappe.throw("Payment allocation must be positive")
    if allocated_amount - outstanding > AMOUNT_TOLERANCE:
        frappe.throw("Payment allocation exceeds Sales Invoice outstanding amount")

    receivable_row = frappe.db.get_value(
        "Account",
        sales_invoice.debit_to,
        [
            "company",
            "account_currency",
            "account_type",
            "is_group",
            "disabled",
        ],
        as_dict=True,
    )
    if not receivable_row:
        frappe.throw("Sales Invoice receivable account is missing")
    if (
        receivable_row.company != COMPANY
        or receivable_row.is_group
        or receivable_row.disabled
    ):
        frappe.throw("Sales Invoice receivable account is unusable")

    receivable_currency = receivable_row.account_currency or CURRENCY
    if receivable_currency != CURRENCY:
        frappe.throw("Sales Invoice receivable account currency must be MMK")

    pe = frappe.new_doc("Payment Entry")
    pe.flags.ignore_permissions = True
    pe.payment_type = "Receive"
    pe.company = COMPANY
    pe.posting_date = frappe.utils.nowdate()
    pe.mode_of_payment = allocation["mode_of_payment"]
    pe.party_type = "Customer"
    pe.party = sales_invoice.customer
    pe.paid_from = sales_invoice.debit_to
    pe.paid_to = allocation["account"]
    pe.paid_from_account_currency = receivable_currency
    pe.paid_to_account_currency = allocation["account_currency"]
    pe.paid_from_account_type = receivable_row.account_type
    pe.paid_to_account_type = allocation["account_type"]
    pe.source_exchange_rate = 1
    pe.target_exchange_rate = 1
    pe.paid_amount = allocated_amount
    pe.received_amount = allocated_amount
    pe.reference_no = (
        sales_invoice.name
        + "-"
        + allocation["mode_of_payment"]
        + "-"
        + str(sequence)
    )
    pe.reference_date = frappe.utils.nowdate()

    if sales_invoice.cost_center:
        pe.cost_center = sales_invoice.cost_center
    if sales_invoice.project:
        pe.project = sales_invoice.project

    pe.append(
        "references",
        {
            "reference_doctype": "Sales Invoice",
            "reference_name": sales_invoice.name,
            "total_amount": float(sales_invoice.grand_total or 0),
            "outstanding_amount": outstanding,
            "allocated_amount": allocated_amount,
        },
    )

    pe.insert(ignore_permissions=True)
    pe.flags.ignore_permissions = True
    pe.submit()
    return pe.name


def build_bill_row(order, has_print_job_doctype, get_linked_draft_sales_invoice_names=get_linked_draft_sales_invoice_names):
    sales_order = frappe.get_doc("Sales Order", order.name)

    item_rows = []
    for item in sales_order.items:
        item_rows.append(
            {
                "item_code": item.item_code,
                "item_name": item.item_name,
                "description": item.description,
                "qty": float(item.qty or 0),
                "uom": item.uom,
                "rate": float(item.rate or 0),
                "amount": float(item.amount or 0),
                "net_amount": float(item.net_amount or 0),
                "custom_foc": int(bool(item.get("custom_foc"))),
            }
        )

    tax_rows = []
    for tax in sales_order.taxes:
        tax_rows.append(
            {
                "charge_type": tax.charge_type,
                "account_head": tax.account_head,
                "description": tax.description,
                "rate": float(tax.rate or 0),
                "tax_amount": float(tax.tax_amount or 0),
                "total": float(tax.total or 0),
            }
        )

    draft_invoice = None
    if order.custom_restaurant_status == "Payment Pending" and order.docstatus == 1:
        draft_invoices = get_linked_draft_sales_invoice_names(order.name)
        if len(draft_invoices) == 1:
            draft_invoice = draft_invoices[0]

    last_print_status = None
    last_print_job = None
    if has_print_job_doctype:
        print_rows = frappe.get_all(
            "BCN Print Job",
            filters={
                "document_type": "Sales Order",
                "document_name": order.name,
            },
            fields=["name", "status"],
            order_by="creation desc",
            limit_page_length=1,
        )
        if print_rows:
            last_print_job = print_rows[0].name
            last_print_status = print_rows[0].status

    return {
        "sales_order": order.name,
        "sales_invoice": draft_invoice,
        "customer": order.customer,
        "customer_name": order.customer_name or order.customer,
        "creation": str(order.creation),
        "net_total": float(order.net_total or 0),
        "total_taxes_and_charges": float(order.total_taxes_and_charges or 0),
        "grand_total": float(order.grand_total or 0),
        "currency": order.currency,
        "restaurant_status": order.custom_restaurant_status,
        "payment_enabled": bool(draft_invoice) or (order.docstatus == 0 and order.custom_restaurant_status in ["Open", "Billing"]),
        "last_print_status": last_print_status,
        "last_print_job": last_print_job,
        "items": item_rows,
        "taxes": tax_rows,
    }


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
    or "Restaurant Manager" in roles
    or "Cashier" in roles
)

if not allowed_user:
    frappe.throw("You are not allowed to use cashier billing.")

action = (frappe.form_dict.get("action") or "").strip()

if action == "Customers":
    search_text = (frappe.form_dict.get("search") or "").strip()
    filters = {"disabled": 0, "customer_group": "Credit"}
    if search_text:
        filters["customer_name"] = ["like", "%" + search_text + "%"]
    customers = frappe.get_all(
        "Customer",
        filters=filters,
        fields=["name", "customer_name"],
        order_by="customer_name asc",
        limit_page_length=60,
    )
    frappe.response["message"] = {
        "customers": [
            {"name": row.name, "customer_name": row.customer_name or row.name}
            for row in customers
        ]
    }

elif action == "ItemSalesReport":
    # Read-only item sales summary and invoice-level detail for one date.
    # FOC and Parcel belong to Sales Order Item, not Item Master.
    report_date = (frappe.form_dict.get("date") or "").strip()
    if len(report_date) != 10:
        frappe.throw("date is required in YYYY-MM-DD format")
    try:
        parsed_date = frappe.utils.getdate(report_date)
    except Exception:
        frappe.throw("Invalid report date")
    if str(parsed_date) != report_date:
        frappe.throw("Invalid report date")

    invoice_rows = []
    page_start = 0
    page_size = 500
    while True:
        page = frappe.get_all(
            "Sales Invoice",
            filters={
                "company": COMPANY,
                "docstatus": 1,
                "posting_date": report_date,
                "is_return": 0,
            },
            fields=["name", "customer", "customer_name", "posting_time", "currency"],
            order_by="posting_time asc, name asc",
            start=page_start,
            page_length=page_size,
        )
        invoice_rows.extend(page)
        if len(page) < page_size:
            break
        page_start += page_size

    invoice_map = {}
    invoice_names = []
    for invoice in invoice_rows:
        invoice_map[invoice.name] = invoice
        invoice_names.append(invoice.name)

    item_rows = []
    for chunk_start in range(0, len(invoice_names), 100):
        chunk = invoice_names[chunk_start:chunk_start + 100]
        page_start = 0
        while True:
            page = frappe.get_all(
                "Sales Invoice Item",
                filters={"parent": ["in", chunk], "parenttype": "Sales Invoice"},
                fields=[
                    "parent", "item_code", "item_name", "qty", "uom",
                    "rate", "net_amount", "so_detail", "sales_order",
                ],
                order_by="parent asc, idx asc",
                start=page_start,
                page_length=500,
            )
            item_rows.extend(page)
            if len(page) < 500:
                break
            page_start += 500

    # Resolve Item Group from Item Master in batches.
    item_codes = []
    for row in item_rows:
        item_code = (row.item_code or "").strip()
        if item_code and item_code not in item_codes:
            item_codes.append(item_code)
    item_group_map = {}
    for chunk_start in range(0, len(item_codes), 100):
        master_rows = frappe.get_all(
            "Item",
            filters={"name": ["in", item_codes[chunk_start:chunk_start + 100]]},
            fields=["name", "item_group"],
            limit_page_length=100,
        )
        for master_row in master_rows:
            item_group_map[master_row.name] = master_row.item_group or ""

    source_names = []
    for row in item_rows:
        source_name = (row.so_detail or "").strip()
        if source_name and source_name not in source_names:
            source_names.append(source_name)

    source_map = {}
    for chunk_start in range(0, len(source_names), 100):
        source_rows = frappe.get_all(
            "Sales Order Item",
            filters={"name": ["in", source_names[chunk_start:chunk_start + 100]]},
            fields=["name", "custom_foc", "custom_parcel"],
            limit_page_length=100,
        )
        for source in source_rows:
            source_map[source.name] = source

    groups = {}
    details = []
    total_qty = 0.0
    foc_qty = 0.0
    parcel_qty = 0.0
    total_amount = 0.0
    unlinked_qty = 0.0

    for row in item_rows:
        invoice = invoice_map.get(row.parent)
        if not invoice:
            continue
        qty = float(row.qty or 0)
        amount = float(row.net_amount or 0)
        source = source_map.get((row.so_detail or "").strip())
        # Do not silently classify unlinked invoice items as normal sales.
        linked = bool(source)
        foc = bool(source.custom_foc) if linked else False
        parcel = bool(source.custom_parcel) if linked else False
        item_group = item_group_map.get((row.item_code or "").strip(), "")
        key = (row.item_code or "", row.item_name or "", row.uom or "", item_group)
        if key not in groups:
            groups[key] = {
                "item_code": key[0], "item_name": key[1],
                "uom": key[2], "item_group": key[3],
                "total_qty": 0.0, "sales_qty": 0.0,
                "foc_qty": 0.0, "parcel_qty": 0.0,
                "sales_amount": 0.0, "unlinked_qty": 0.0, "avg_rate": 0.0,
            }
        entry = groups[key]
        entry["total_qty"] = entry["total_qty"] + qty
        entry["sales_amount"] = entry["sales_amount"] + amount
        if foc:
            entry["foc_qty"] = entry["foc_qty"] + qty
            foc_qty += qty
        elif linked:
            entry["sales_qty"] = entry["sales_qty"] + qty
        else:
            entry["unlinked_qty"] = entry["unlinked_qty"] + qty
            unlinked_qty += qty
        if parcel:
            entry["parcel_qty"] = entry["parcel_qty"] + qty
            parcel_qty += qty
        total_qty += qty
        total_amount += amount

        details.append({
            "invoice": row.parent,
            "customer": invoice.customer_name or invoice.customer or "",
            "sales_order": row.sales_order or "",
            "time": str(invoice.posting_time or ""),
            "item_code": row.item_code or "",
            "item_name": row.item_name or row.item_code or "",
            "item_group": item_group,
            "qty": qty, "uom": row.uom or "",
            "rate": float(row.rate or 0), "amount": amount,
            "foc": foc, "parcel": parcel, "flags_linked": linked,
        })

    summary = []
    for group in groups.values():
        # Average net item amount per unit; FOC quantities are included.
        group["avg_rate"] = (
            group["sales_amount"] / group["total_qty"]
            if abs(group["total_qty"]) > 0.00001 else 0.0
        )
        summary.append(group)
    summary.sort(key=lambda row: (-row["sales_amount"], row["item_name"]))
    available_item_groups = sorted(set(
        row["item_group"] for row in summary if row["item_group"]
    ))

    frappe.response["message"] = {
        "date": report_date, "currency": CURRENCY,
        "invoice_count": len(invoice_rows),
        "item_count": len(summary),
        "total_qty": total_qty, "foc_qty": foc_qty,
        "parcel_qty": parcel_qty, "unlinked_qty": unlinked_qty,
        "total_amount": total_amount,
        "amount_basis": "Sales Invoice Item net_amount; excludes invoice-level discounts and taxes",
        "item_groups": available_item_groups,
        "summary": summary, "details": details,
    }

elif action == "DailyReport":
    report_date = (frappe.form_dict.get("date") or "").strip()
    if not report_date or len(report_date) != 10:
        frappe.throw("date is required in YYYY-MM-DD format")
    try:
        parsed_date = frappe.utils.getdate(report_date)
    except Exception:
        frappe.throw("Invalid report date")
    if str(parsed_date) != report_date:
        frappe.throw("Invalid report date")

    # Page through all invoices rather than silently truncating daily totals.
    invoice_rows = []
    page_start = 0
    page_size = 500
    while True:
        page = frappe.get_all(
            "Sales Invoice",
            filters={
                "company": COMPANY,
                "docstatus": 1,
                "posting_date": report_date,
                "is_return": 0,
            },
            fields=[
                "name", "customer_name", "customer", "posting_time",
                "grand_total", "outstanding_amount", "currency"
            ],
            order_by="posting_time asc, name asc",
            start=page_start,
            page_length=page_size,
        )
        invoice_rows.extend(page)
        if len(page) < page_size:
            break
        page_start += page_size

    # Submitted Payment Entries allocated to these Sales Invoices.
    # This is the current allocated breakdown, not daily cash collection.
    payment_by_invoice = {}
    payment_totals = {}
    invoice_names = [row.name for row in invoice_rows]
    for chunk_start in range(0, len(invoice_names), 100):
        names = invoice_names[chunk_start:chunk_start + 100]
        references = frappe.get_all(
            "Payment Entry Reference",
            filters={
                "reference_doctype": "Sales Invoice",
                "reference_name": ["in", names],
                "docstatus": 1,
            },
            fields=["parent", "reference_name", "allocated_amount"],
            limit_page_length=10000,
        )
        payment_names = []
        for ref in references:
            if ref.parent not in payment_names:
                payment_names.append(ref.parent)
        modes = {}
        if payment_names:
            entries = frappe.get_all(
                "Payment Entry",
                filters={"name": ["in", payment_names], "docstatus": 1},
                fields=["name", "mode_of_payment", "payment_type"],
                limit_page_length=10000,
            )
            for entry in entries:
                modes[entry.name] = entry
        for ref in references:
            entry = modes.get(ref.parent)
            if not entry:
                continue
            mode = (entry.mode_of_payment or "Other").strip()
            allocated = float(ref.allocated_amount or 0)
            if entry.payment_type == "Pay":
                allocated = -allocated
            if abs(allocated) < 0.00001:
                continue
            details = payment_by_invoice.setdefault(ref.reference_name, {})
            details[mode] = details.get(mode, 0.0) + allocated
            payment_totals[mode] = payment_totals.get(mode, 0.0) + allocated

    # Resolve the Sales Order linked to each submitted Sales Invoice.
    # Fetch in batches to avoid N+1 queries for a busy restaurant day.
    sales_orders_by_invoice = {}
    for chunk_start in range(0, len(invoice_names), 100):
        names = invoice_names[chunk_start:chunk_start + 100]
        invoice_items = frappe.get_all(
            "Sales Invoice Item",
            filters={
                "parent": ["in", names],
                "parenttype": "Sales Invoice",
            },
            fields=["parent", "sales_order"],
            limit_page_length=10000,
        )
        for invoice_item in invoice_items:
            linked_order = (invoice_item.sales_order or "").strip()
            if not linked_order:
                continue
            orders = sales_orders_by_invoice.setdefault(
                invoice_item.parent, []
            )
            if linked_order not in orders:
                orders.append(linked_order)

    total_sales = 0.0
    total_outstanding = 0.0
    invoices = []
    for row in invoice_rows:
        grand = float(row.grand_total or 0)
        outstanding = float(row.outstanding_amount or 0)
        total_sales += grand
        total_outstanding += outstanding
        linked_orders = sales_orders_by_invoice.get(row.name, [])
        # An invoice spanning multiple orders cannot safely be reprinted
        # through the cashier API, which expects exactly one Sales Order.
        linked_sales_order = linked_orders[0] if len(linked_orders) == 1 else ""
        invoices.append({
            "name": row.name,
            "sales_order": linked_sales_order,
            "customer": row.customer_name or row.customer,
            "time": str(row.posting_time or ""),
            "grand_total": grand,
            "outstanding": outstanding,
            "paid": grand - outstanding,
            "payment_methods": [
                {"name": mode, "amount": value}
                for mode, value in payment_by_invoice.get(row.name, {}).items()
                if abs(value) > 0.00001
            ],
        })
    frappe.response["message"] = {
        "date": report_date,
        "currency": CURRENCY,
        "invoice_count": len(invoices),
        "total_sales": total_sales,
        "total_paid": total_sales - total_outstanding,
        "total_outstanding": total_outstanding,
        "invoices": invoices,
        "payment_method_summary": [
            {"name": mode, "amount": value}
            for mode, value in sorted(payment_totals.items())
            if abs(value) > 0.00001
        ],
    }

elif action == "StartCheckout":
    # Pay and Credit both call this BEFORE any selection dialogs.
    # Locking the Sales Order makes repeated taps and retries idempotent.
    sales_order_name = (frappe.form_dict.get("sales_order") or "").strip()
    if not sales_order_name:
        frappe.throw("sales_order is required")
    locked_rows = frappe.db.sql(
        "SELECT name FROM `tabSales Order` WHERE name=%(name)s FOR UPDATE",
        {"name": sales_order_name}, as_dict=True,
    )
    if not locked_rows:
        frappe.throw("Sales Order not found")
    so = frappe.get_doc("Sales Order", sales_order_name)
    if so.company != COMPANY or so.currency != CURRENCY:
        frappe.throw("Restaurant company/currency mismatch")

    state = (so.get("custom_restaurant_status") or "").strip()
    if so.docstatus == 0 and state == "Open":
        if not so.items:
            frappe.throw("Sales Order has no items")
        check_in = frappe.utils.get_datetime(
            so.get("custom_check_in") or so.creation
        )
        # Preserve a previously stored checkout time under all circumstances.
        now = frappe.utils.get_datetime(
            so.get("custom_check_out") or frappe.utils.now_datetime()
        )
        elapsed = (now - check_in).total_seconds()
        if elapsed < 0:
            frappe.throw("Check-out cannot be before check-in")
        half_hours = max(2, int((elapsed + 1799.999999) // 1800))
        billable = half_hours / 2.0
        room_rows = []
        has_room_flag = frappe.get_meta("Item").has_field("custom_is_room_charge")
        for row in so.items:
            item_group = frappe.db.get_value("Item", row.item_code, "item_group") or ""
            flag = (
                frappe.db.get_value("Item", row.item_code, "custom_is_room_charge")
                if has_room_flag else False
            )
            if flag or item_group.strip().lower() == "room charges":
                room_rows.append(row)
        if len(room_rows) > 1:
            frappe.throw("Only one Room Charges item is allowed")
        if room_rows:
            if room_rows[0].uom != "Hour":
                frappe.throw("Room Charges UOM must be Hour")
            room_rows[0].qty = billable
        so.custom_check_in = check_in
        so.custom_check_out = now
        so.custom_duration = elapsed / 3600.0
        so.custom_billable_hours = billable if room_rows else 0
        so.custom_bill_revision = int(so.get("custom_bill_revision") or 0) + 1
        so.custom_restaurant_status = "Billing"
        so.calculate_taxes_and_totals()
        so.save(ignore_permissions=True)
    elif so.docstatus == 0 and state == "Billing":
        if not so.get("custom_check_out"):
            frappe.throw("Billing order has no locked check-out time")
    elif so.docstatus == 1 and state == "Payment Pending":
        if not so.get("custom_check_out"):
            frappe.throw("Payment Pending order has no check-out time")
    else:
        frappe.throw("Only an active restaurant order can start checkout")

    frappe.response["message"] = {
        "success": True,
        "sales_order": so.name,
        "check_out": str(so.get("custom_check_out")),
        "billable_hours": float(so.get("custom_billable_hours") or 0),
        "room_charges_locked": True,
        "restaurant_status": so.custom_restaurant_status,
        "grand_total": float(so.grand_total or 0),
    }

elif action == "Pay":
    sales_order_name = (frappe.form_dict.get("sales_order") or "").strip()
    if not sales_order_name:
        frappe.throw("sales_order is required")
    locked_rows = frappe.db.sql(
        "SELECT name FROM `tabSales Order` WHERE name=%(name)s FOR UPDATE",
        {"name": sales_order_name}, as_dict=True,
    )
    if not locked_rows:
        frappe.throw("Sales Order not found")
    so = frappe.get_doc("Sales Order", sales_order_name)
    if so.company != COMPANY or so.currency != CURRENCY:
        frappe.throw("Restaurant company/currency mismatch")

    state = (so.get("custom_restaurant_status") or "").strip()
    if so.docstatus == 1 and state in ["Payment Pending", "Closed"]:
        requested_credit_customer = (frappe.form_dict.get("credit_customer") or "").strip()
        if requested_credit_customer and requested_credit_customer != so.customer:
            frappe.throw(
                "Credit Customer cannot be changed after Sales Order submission. "
                "Finish the existing checkout or ask an administrator to correct it."
            )
        invoices = (
            get_linked_draft_sales_invoice_names(so.name)
            if state == "Payment Pending"
            else get_linked_submitted_sales_invoice_names(so.name)
        )
        if len(invoices) != 1:
            frappe.throw("Submitted order must have exactly one linked Sales Invoice")
        frappe.response["message"] = {
            "sales_order": so.name, "sales_invoice": invoices[0],
            "restaurant_status": state, "duplicate": True,
        }
    elif so.docstatus == 0 and state in ["Open", "Billing"]:
        # Checkout timestamp must already have been locked by StartCheckout.
        # Do not recalculate it while selecting a Credit Customer or retrying Pay.
        if state != "Billing" or not so.get("custom_check_out"):
            frappe.throw("Start checkout before preparing payment")
        selected_customer = (frappe.form_dict.get("credit_customer") or "").strip()
        if selected_customer:
            customer = frappe.db.get_value(
                "Customer", selected_customer,
                ["name", "customer_name", "disabled"],
                as_dict=True,
            )
            if not customer or customer.disabled:
                frappe.throw("Select a valid active Credit Customer")
            if frappe.db.get_value("Customer", customer.name, "customer_group") != "Credit":
                frappe.throw("Selected customer must belong to Credit Customer Group")
            original_grand = float(so.grand_total or 0)
            original_net = float(so.net_total or 0)
            original_tax = float(so.total_taxes_and_charges or 0)
            so.customer = customer.name
            so.customer_name = customer.customer_name or customer.name
            so.save(ignore_permissions=True)
            validate_invoice_totals(so, original_net, original_tax, original_grand)
        if not int(so.get("custom_bill_revision") or 0):
            frappe.throw("Please request bill before Pay")
        if get_linked_draft_sales_invoice_names(so.name):
            frappe.throw("Unexpected Draft Invoice exists before Pay")
        so.custom_restaurant_status = "Payment Pending"
        so.flags.ignore_permissions = True
        so.submit()
        si = frappe.call(
            "erpnext.selling.doctype.sales_order.sales_order.make_sales_invoice",
            source_name=so.name, ignore_permissions=True,
        )
        si.flags.ignore_permissions = True
        si.update_stock = 1
        si.calculate_taxes_and_totals()
        validate_invoice_totals(
            si, float(so.net_total or 0),
            float(so.total_taxes_and_charges or 0), float(so.grand_total or 0),
        )
        si.insert(ignore_permissions=True)
        frappe.response["message"] = {
            "sales_order": so.name, "sales_invoice": si.name,
            "restaurant_status": "Payment Pending", "duplicate": False,
        }
    else:
        frappe.throw("Only latest billed Draft Sales Orders can be paid")

elif action == "ConfirmPayment":
    sales_order_name = (frappe.form_dict.get("sales_order") or "").strip()
    raw_payments = frappe.form_dict.get("payments")
    payment_type = (frappe.form_dict.get("payment_type") or "Paid").strip()
    credit_amount = float(frappe.form_dict.get("credit_amount") or 0)
    discount_amount = float(frappe.form_dict.get("discount_amount") or 0)
    credit_remark = (frappe.form_dict.get("credit_remark") or "").strip()
    if payment_type not in ("Paid", "Credit", "Partial Credit"):
        frappe.throw("Invalid cashier payment_type")
    if credit_amount < 0:
        frappe.throw("Credit amount cannot be negative")
    if payment_type in ("Credit", "Partial Credit") and not credit_remark:
        frappe.throw("Credit customer name is required in Remark")
    if payment_type == "Paid" and credit_amount > AMOUNT_TOLERANCE:
        frappe.throw("Paid transaction cannot include credit amount")

    if not sales_order_name:
        frappe.throw("sales_order is required")

    locked_rows = frappe.db.sql(
        "SELECT name FROM `tabSales Order` WHERE name=%(name)s FOR UPDATE",
        {"name": sales_order_name},
        as_dict=True,
    )
    if not locked_rows:
        frappe.throw("Sales Order not found: " + sales_order_name)

    sales_order = frappe.get_doc("Sales Order", sales_order_name)
    if sales_order.company != COMPANY:
        frappe.throw("Sales Order does not belong to the restaurant company")
    if sales_order.currency != CURRENCY:
        frappe.throw("Restaurant checkout requires MMK Sales Order currency")
    profile = frappe.get_doc("POS Profile", POS_PROFILE)
    # Never accept zero tender for a normal order. All line flags and the
    # frozen Sales Order grand total must both establish an FOC-only order.
    all_foc = bool(sales_order.items) and all(
        bool(row.get("custom_foc")) for row in sales_order.items
    )
    free_foc = (
        all_foc
        and abs(float(sales_order.grand_total or 0)) <= AMOUNT_TOLERANCE
    )
    tenders = parse_tenders(
        raw_payments,
        profile,
        allow_empty=payment_type == "Credit" or free_foc,
    )
    restaurant_status = (
        sales_order.get("custom_restaurant_status") or ""
    ).strip()

    if sales_order.docstatus == 1 and restaurant_status == "Closed":
        linked_invoices = get_linked_submitted_sales_invoice_names(
            sales_order.name
        )
        if not linked_invoices:
            frappe.throw("Closed Sales Order has no submitted linked Sales Invoice")
        if len(linked_invoices) > 1:
            frappe.throw(
                "Closed Sales Order has multiple submitted linked Sales Invoices"
            )

        sales_invoice = frappe.get_doc("Sales Invoice", linked_invoices[0])
        payment_entries = get_linked_payment_entry_names(sales_invoice.name)
        final_outstanding = float(
            frappe.db.get_value(
                "Sales Invoice",
                sales_invoice.name,
                "outstanding_amount",
            ) or 0
        )
        # Idempotent retry: closed orders may legally remain Unpaid or Partly Paid.
        # Do not re-create Payment Entries or replace the original credit remark.
        expected_outstanding = (
            float(sales_invoice.grand_total or 0)
            if payment_type == "Credit" else credit_amount
        )
        if abs(final_outstanding - expected_outstanding) > AMOUNT_TOLERANCE:
            frappe.throw("Closed invoice outstanding does not match this retry")
        if payment_type in ("Credit", "Partial Credit") and (
            (sales_invoice.remarks or "").strip() != credit_remark
        ):
            frappe.throw("Closed invoice credit remark does not match this retry")
        change_amount = 0.0

        frappe.response["message"] = {
            "sales_order": sales_order.name,
            "sales_invoice": sales_invoice.name,
            "payment_entries": payment_entries,
            "change_amount": float(change_amount),
            "duplicate": True,
        }

    elif sales_order.docstatus == 1 and restaurant_status == "Payment Pending":
        draft_invoices = get_linked_draft_sales_invoice_names(
            sales_order.name
        )
        if not draft_invoices:
            frappe.throw(
                "Bill Requested Sales Order has no Draft Sales Invoice"
            )
        if len(draft_invoices) > 1:
            frappe.throw("Sales Order has multiple Draft Sales Invoices")

        sales_invoice = frappe.get_doc("Sales Invoice", draft_invoices[0])
        if sales_invoice.docstatus != 0:
            frappe.throw("Linked Sales Invoice is not Draft")

        frozen_net = float(sales_order.net_total or 0)
        frozen_taxes = float(sales_order.total_taxes_and_charges or 0)
        frozen_grand = float(sales_order.grand_total or 0)

        sales_invoice.update_stock = 1
        sales_invoice.calculate_taxes_and_totals()
        validate_invoice_totals(
            sales_invoice,
            frozen_net,
            frozen_taxes,
            frozen_grand,
        )

        # The mobile payment sheet already subtracts Discount Amount from the
        # frozen bill. Persist that same discount on the Draft Sales Invoice
        # BEFORE validating tenders or submitting the invoice.
        # Keep the submitted Sales Order (and its room charges) untouched.
        if free_foc:
            if payment_type != "Paid":
                frappe.throw("FOC checkout must use Paid without credit")
            if tenders or credit_amount > AMOUNT_TOLERANCE or discount_amount != 0:
                frappe.throw("FOC checkout must not include tender, credit or discount")
        elif not (0 <= discount_amount < frozen_grand):
            frappe.throw("Discount must be zero or less than the original invoice total")
        sales_invoice.apply_discount_on = "Grand Total"
        sales_invoice.discount_amount = discount_amount
        sales_invoice.calculate_taxes_and_totals()
        grand_total = float(sales_invoice.grand_total or 0)
        expected_grand = frozen_grand - discount_amount
        if abs(grand_total - expected_grand) > AMOUNT_TOLERANCE:
            frappe.throw(
                "Discounted invoice total does not match net payable: "
                + str(grand_total) + " vs " + str(expected_grand)
            )
        if free_foc:
            # No money is collected: submit the zero-value Sales Invoice,
            # skip Payment Entry creation, and close the order normally.
            if abs(grand_total) > AMOUNT_TOLERANCE:
                frappe.throw("FOC invoice total must be zero")
            expected_credit = 0.0
            allocations = []
            change_amount = 0.0
        elif payment_type == "Credit":
            if tenders:
                frappe.throw("Full Credit must not include payment tenders")
            if credit_amount > AMOUNT_TOLERANCE and abs(credit_amount - grand_total) > AMOUNT_TOLERANCE:
                frappe.throw("Full Credit must equal invoice total")
            expected_credit = grand_total
            allocations = []
            change_amount = 0.0
        else:
            if payment_type == "Partial Credit":
                if credit_amount <= AMOUNT_TOLERANCE or credit_amount >= grand_total - AMOUNT_TOLERANCE:
                    frappe.throw("Partial Credit must be between zero and invoice total")
                expected_credit = credit_amount
            else:
                expected_credit = 0.0
            paid_due = grand_total - expected_credit
            allocation_result = allocate_tenders(tenders, paid_due)
            allocations = allocation_result[0]
            change_amount = allocation_result[1]
            if change_amount > AMOUNT_TOLERANCE:
                frappe.throw("Split payment does not allow excess cash")
            total_allocated = 0.0
            for allocation_row in allocations:
                total_allocated += float(
                    allocation_row.get("allocated_amount") or 0
                )
            if abs(total_allocated - paid_due) > AMOUNT_TOLERANCE:
                frappe.throw("Payment total does not match invoice less credit")

        sales_invoice.is_pos = 0
        sales_invoice.set("payments", [])
        sales_invoice.paid_amount = 0
        if payment_type in ("Credit", "Partial Credit"):
            sales_invoice.remarks = credit_remark
        sales_invoice.flags.ignore_permissions = True
        sales_invoice.save(ignore_permissions=True)
        sales_invoice.submit()

        payment_entries = []
        sequence = 1
        for allocation in allocations:
            payment_entries.append(
                make_payment_entry(
                    sales_invoice,
                    allocation,
                    sequence,
                )
            )
            sequence = sequence + 1

        final_outstanding = float(
            frappe.db.get_value(
                "Sales Invoice",
                sales_invoice.name,
                "outstanding_amount",
            )
            or 0
        )
        if abs(final_outstanding - expected_credit) > AMOUNT_TOLERANCE:
            frappe.throw(
                "Sales Invoice outstanding does not match credit amount: "
                + str(final_outstanding)
            )

        frappe.db.set_value(
            "Sales Order",
            sales_order.name,
            "custom_restaurant_status",
            "Closed",
            update_modified=True,
        )

        frappe.response["message"] = {
            "sales_order": sales_order.name,
            "sales_invoice": sales_invoice.name,
            "payment_entries": payment_entries,
            "change_amount": float(change_amount),
            "outstanding_amount": float(final_outstanding),
            "duplicate": False,
        }

    elif sales_order.docstatus == 0 and restaurant_status == "Open":
        frappe.throw("Please request the bill before taking payment")
    else:
        frappe.throw("Sales Order is not in a payable restaurant state")

elif action:
    frappe.throw("Unsupported cashier billing action: " + action)

else:
    ordering_orders = frappe.get_all(
        "Sales Order",
        filters={
            "company": COMPANY,
            "docstatus": 0,
            "custom_restaurant_status": "Open",
        },
        fields=[
            "name",
            "customer",
            "customer_name",
            "creation",
            "net_total",
            "total_taxes_and_charges",
            "grand_total",
            "currency",
            "docstatus",
            "custom_restaurant_status",
        ],
        order_by="creation asc",
        limit_page_length=500,
    )

    billing_orders = frappe.get_all(
        "Sales Order",
        filters={
            "company": COMPANY,
            "docstatus": 0,
            "custom_restaurant_status": "Billing",
        },
        fields=[
            "name",
            "customer",
            "customer_name",
            "creation",
            "net_total",
            "total_taxes_and_charges",
            "grand_total",
            "currency",
            "docstatus",
            "custom_restaurant_status",
        ],
        order_by="creation asc",
        limit_page_length=500,
    )

    pending_orders = frappe.get_all(
        "Sales Order",
        filters={"company": COMPANY, "docstatus": 1, "custom_restaurant_status": "Payment Pending"},
        fields=["name", "customer", "customer_name", "creation", "net_total", "total_taxes_and_charges", "grand_total", "currency", "docstatus", "custom_restaurant_status"],
        order_by="creation asc", limit_page_length=500,
    )
    orders = ordering_orders + billing_orders + pending_orders
    orders = sorted(
        orders,
        key=lambda row: str(row.creation or ""),
    )

    has_print_job_doctype = bool(
        frappe.db.exists("DocType", "BCN Print Job")
    )
    bills = []
    for order in orders:
        bills.append(build_bill_row(order, has_print_job_doctype))

    profile = frappe.get_doc("POS Profile", POS_PROFILE)
    modes = []
    seen_modes = []

    for payment in profile.payments:
        mode_name = (payment.mode_of_payment or "").strip()
        if mode_name and mode_name not in seen_modes:
            seen_modes.append(mode_name)
            modes.append(
                {
                    "name": mode_name,
                    "default": bool(payment.default),
                }
            )

    frappe.response["message"] = {
        "bills": bills,
        "modes": modes,
    }
