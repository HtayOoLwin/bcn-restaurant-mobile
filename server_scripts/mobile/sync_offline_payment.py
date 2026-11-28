# Server Script API: bcn_sync_offline_payment
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

# Offline cash settlement is intentionally limited to unchanged, non-room bills.
# Requires BCN Offline Payment Sync (autoname field:request_id).
SYNC_DOCTYPE = "BCN Offline Payment Sync"
action = (frappe.form_dict.get("action") or "").strip()
if not frappe.db.exists("DocType", SYNC_DOCTYPE):
    frappe.throw("Missing DocType: " + SYNC_DOCTYPE)
if action == "ping":
    frappe.response["message"] = {"ready": True, "backend_version": 2}
elif action == "submit":
    request_id = (frappe.form_dict.get("request_id") or "").strip()
    order_name = (frappe.form_dict.get("sales_order") or "").strip()
    customer = (frappe.form_dict.get("customer") or "").strip()
    expected_modified = (frappe.form_dict.get("expected_modified") or "").strip()
    amount = float(frappe.form_dict.get("amount") or 0)
    mode = (frappe.form_dict.get("mode_of_payment") or "").strip()
    received_at = (frappe.form_dict.get("received_at") or "").strip()
    credit_customer = (frappe.form_dict.get("credit_customer") or "").strip()
    if credit_customer and mode:
        frappe.throw("Full credit must not include cash")
    if not request_id.startswith("offline-pay:") or len(request_id) > 140:
        frappe.throw("Invalid offline payment request ID")
    if not order_name or not customer or not expected_modified or not received_at or not (0 < amount < 1000000000000):
        frappe.throw("Invalid offline payment payload")
    payload = json.dumps({"sales_order": order_name, "customer": customer,
        "expected_modified": expected_modified, "amount": amount,
        "mode_of_payment": mode, "received_at": received_at}, sort_keys=True)
    if credit_customer:
        payload = json.dumps({"sales_order": order_name, "customer": customer,
            "expected_modified": expected_modified, "amount": amount,
            "mode_of_payment": mode, "received_at": received_at,
            "credit_customer": credit_customer}, sort_keys=True)
    frappe.db.sql("SELECT name FROM `tabCustomer` WHERE name=%(name)s FOR UPDATE",
        {"name": customer})
    locked = frappe.db.sql("SELECT name FROM `tabSales Order` WHERE name=%(name)s FOR UPDATE",
        {"name": order_name})
    if not locked:
        frappe.throw("PAYMENT CONFLICT: Sales Order does not exist")
    receipts = frappe.db.sql("SELECT name, company, request_user, payload_json, sales_invoice, sales_order "
        "FROM `tabBCN Offline Payment Sync` WHERE name=%(name)s FOR UPDATE",
        {"name": request_id}, as_dict=True)
    if receipts:
        receipt = receipts[0]
        if receipt.company != COMPANY or receipt.request_user != current_user or receipt.payload_json != payload:
            frappe.throw("PAYMENT CONFLICT: Request ID does not match recorded payment")
        frappe.response["message"] = {"success": True, "duplicate": True,
            "sales_order": receipt.sales_order, "sales_invoice": receipt.sales_invoice}
    else:
        so = frappe.get_doc("Sales Order", order_name)
        if so.company != COMPANY or so.currency != CURRENCY or so.customer != customer:
            frappe.throw("PAYMENT CONFLICT: Customer/company/currency changed")
        state = (so.get("custom_restaurant_status") or "").strip()
        if so.docstatus != 0 or state not in ("Open", "Billing"):
            frappe.throw("PAYMENT CONFLICT: Order is no longer an open draft bill")
        if str(so.modified) != expected_modified:
            frappe.throw("PAYMENT CONFLICT: Bill changed after offline snapshot")
        if abs(float(so.grand_total or 0) - amount) > AMOUNT_TOLERANCE:
            frappe.throw("PAYMENT CONFLICT: Bill total differs from collected cash")
        if not so.items:
            frappe.throw("Sales Order has no items")
        if get_linked_draft_sales_invoice_names(so.name) or get_linked_submitted_sales_invoice_names(so.name):
            frappe.throw("PAYMENT CONFLICT: Linked invoice already exists")
        profile = frappe.get_doc("POS Profile", POS_PROFILE)
        allocation = None
        credit_name = ""
        if credit_customer:
            credit = frappe.db.get_value("Customer", credit_customer,
                ["name", "customer_name", "customer_group", "disabled"], as_dict=True)
            if not credit or credit.disabled or credit.customer_group != "Credit":
                frappe.throw("PAYMENT CONFLICT: Credit customer is unavailable")
            credit_name = credit.customer_name or credit.name
        else:
            allocation = get_mode_details(profile, mode)
            if not allocation["is_cash"]:
                frappe.throw("Offline settlement only supports Cash or full Credit")
        has_room_flag = frappe.get_meta("Item").has_field("custom_is_room_charge")
        for row in so.items:
            group = frappe.db.get_value("Item", row.item_code, "item_group") or ""
            flag = frappe.db.get_value("Item", row.item_code, "custom_is_room_charge") if has_room_flag else False
            if flag or group.strip().lower() == "room charges":
                frappe.throw("PAYMENT CONFLICT: Room charges require online checkout")
        if state == "Open":
            check_in = frappe.utils.get_datetime(so.get("custom_check_in") or so.creation)
            # Server posting date is the actual sync date; original receipt time
            # remains in the immutable sync receipt.
            checkout = frappe.utils.get_datetime(so.get("custom_check_out") or frappe.utils.now_datetime())
            elapsed = (checkout - check_in).total_seconds()
            if elapsed < 0:
                frappe.throw("Invalid checkout time")
            so.custom_check_in = check_in
            so.custom_check_out = checkout
            so.custom_duration = elapsed / 3600.0
            so.custom_billable_hours = 0
            so.custom_bill_revision = int(so.get("custom_bill_revision") or 0) + 1
        elif not so.get("custom_check_out"):
            frappe.throw("Billing order has no locked checkout")
        frozen_net = float(so.net_total or 0)
        frozen_tax = float(so.total_taxes_and_charges or 0)
        if credit_customer:
            so.customer = credit_customer
            so.customer_name = credit_name
        so.custom_restaurant_status = "Payment Pending"
        so.calculate_taxes_and_totals()
        validate_invoice_totals(so, frozen_net, frozen_tax, amount)
        so.flags.ignore_permissions = True
        so.save(ignore_permissions=True)
        so.submit()
        si = frappe.call("erpnext.selling.doctype.sales_order.sales_order.make_sales_invoice",
            source_name=so.name, ignore_permissions=True)
        si.flags.ignore_permissions = True
        si.update_stock = 1
        si.is_pos = 0
        si.set("payments", [])
        si.paid_amount = 0
        si.calculate_taxes_and_totals()
        validate_invoice_totals(si, frozen_net, frozen_tax, amount)
        if credit_customer:
            si.remarks = credit_name
        si.insert(ignore_permissions=True)
        si.submit()
        payment_entries = []
        if not credit_customer:
            allocation["allocated_amount"] = amount
            payment_entries.append(make_payment_entry(si, allocation, 1))
        outstanding = float(frappe.db.get_value("Sales Invoice", si.name, "outstanding_amount") or 0)
        if abs(outstanding - (amount if credit_customer else 0)) > AMOUNT_TOLERANCE:
            frappe.throw("Offline payment did not settle invoice")
        frappe.db.set_value("Sales Order", so.name, "custom_restaurant_status", "Closed", update_modified=True)
        receipt = frappe.new_doc(SYNC_DOCTYPE)
        receipt.request_id = request_id
        receipt.company = COMPANY
        receipt.request_user = current_user
        receipt.customer = customer
        receipt.sales_order = so.name
        receipt.sales_invoice = si.name
        receipt.payload_json = payload
        receipt.grand_total = amount
        receipt.insert(ignore_permissions=True)
        frappe.response["message"] = {"success": True, "duplicate": False,
            "sales_order": so.name, "sales_invoice": si.name, "payment_entries": payment_entries, "outstanding_amount": outstanding}
else:
    frappe.throw("Unsupported offline payment action")
