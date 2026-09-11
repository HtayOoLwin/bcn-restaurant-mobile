# Server Script API: bcn_cashier_billing
# Deployment target: https://ourcity.s.frappe.cloud
#
# GET:
# - list Open Draft Sales Orders immediately
# - list submitted Billing Sales Orders that have a Draft Sales Invoice
# - include latest BCN Print Job status and DMT payment modes
#
# POST action=Pay:
# - only a submitted Billing Sales Order can be paid
# - submit its existing Draft Sales Invoice with update_stock enabled
# - create submitted Payment Entries for tender allocations
# - close the restaurant Sales Order after successful payment
# - successful response-timeout retries resolve existing final documents
#
# No manual commit/rollback is used.

COMPANY = "Doh Myot Daw BBQ & Restaurant"
POS_PROFILE = "DMT"
CURRENCY = "MMK"
AMOUNT_TOLERANCE = 0.01


def get_mode_details(profile, mode_name):
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


def parse_tenders(raw_payments, profile):
    if isinstance(raw_payments, str):
        rows = json.loads(raw_payments) if raw_payments else []
    elif isinstance(raw_payments, (list, tuple)):
        rows = raw_payments
    else:
        rows = []

    if not rows:
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

    if not tenders:
        frappe.throw("At least one positive payment is required")

    return tenders


def allocate_tenders(tenders, amount_due):
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


def validate_invoice_totals(sales_invoice, frozen_net, frozen_taxes, frozen_grand):
    if abs(float(sales_invoice.net_total or 0) - frozen_net) > AMOUNT_TOLERANCE:
        frappe.throw("Sales Invoice net total does not match the frozen bill")
    if (
        abs(float(sales_invoice.total_taxes_and_charges or 0) - frozen_taxes)
        > AMOUNT_TOLERANCE
    ):
        frappe.throw("Sales Invoice taxes do not match the frozen bill")
    if abs(float(sales_invoice.grand_total or 0) - frozen_grand) > AMOUNT_TOLERANCE:
        frappe.throw("Sales Invoice grand total does not match the frozen bill")


def make_payment_entry(sales_invoice, allocation, sequence):
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


def build_bill_row(order, has_print_job_doctype):
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
    if order.custom_restaurant_status == "Billing" and order.docstatus == 1:
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
        "payment_enabled": bool(draft_invoice),
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

if action == "Pay":
    sales_order_name = (frappe.form_dict.get("sales_order") or "").strip()
    raw_payments = frappe.form_dict.get("payments")

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
    tenders = parse_tenders(raw_payments, profile)
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
        allocations, change_amount = allocate_tenders(
            tenders,
            float(sales_invoice.grand_total or 0),
        )
        payment_entries = get_linked_payment_entry_names(sales_invoice.name)
        final_outstanding = float(
            frappe.db.get_value(
                "Sales Invoice",
                sales_invoice.name,
                "outstanding_amount",
            )
            or 0
        )
        if abs(final_outstanding) > AMOUNT_TOLERANCE:
            frappe.throw("Existing Sales Invoice is not fully paid")

        frappe.response["message"] = {
            "sales_order": sales_order.name,
            "sales_invoice": sales_invoice.name,
            "payment_entries": payment_entries,
            "change_amount": float(change_amount),
            "duplicate": True,
        }

    elif sales_order.docstatus == 1 and restaurant_status == "Billing":
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

        allocations, change_amount = allocate_tenders(
            tenders,
            float(sales_invoice.grand_total or 0),
        )

        sales_invoice.flags.ignore_permissions = True
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
        if abs(final_outstanding) > AMOUNT_TOLERANCE:
            frappe.throw(
                "Sales Invoice outstanding amount is not zero after payment"
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
            "docstatus": 1,
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

    orders = ordering_orders + billing_orders
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
