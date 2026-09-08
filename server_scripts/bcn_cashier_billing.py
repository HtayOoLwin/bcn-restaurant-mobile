# Server Script
# Script Type: API
# API Method: bcn_cashier_billing
# Allow Guest: No


def _request_data():
    payload = frappe.request.get_json(silent=True)
    if not payload:
        payload = frappe.form_dict
    return payload


def _submitted_payment_entries(invoice_name):
    result = []
    rows = frappe.get_all(
        "Payment Entry Reference",
        filters={
            "reference_doctype": "Sales Invoice",
            "reference_name": invoice_name,
        },
        fields=["parent"],
        limit_page_length=100,
    )
    for row in rows:
        name = str(row.get("parent") or "").strip()
        if not name or name in result:
            continue
        if frappe.db.get_value("Payment Entry", name, "docstatus") == 1:
            result.append(name)
    return result


def _mode_account(mode_of_payment, company):
    return frappe.db.get_value(
        "Mode of Payment Account",
        {"parent": mode_of_payment, "company": company},
        "default_account",
    )


def _tax_rows(doc):
    rows = []
    for tax in doc.get("taxes") or []:
        rows.append(
            {
                "description": tax.get("description") or tax.get("account_head") or "Tax",
                "account_head": tax.get("account_head"),
                "charge_type": tax.get("charge_type") or "",
                "rate": float(tax.get("rate") or 0),
                "tax_amount": float(tax.get("tax_amount") or 0),
            }
        )
    return rows


def _item_rows(doc, sales_order_name):
    rows = []
    for item in doc.get("items") or []:
        rows.append(
            {
                "item_code": item.get("item_code") or "",
                "item_name": item.get("item_name") or item.get("item_code") or "",
                "qty": float(item.get("qty") or 0),
                "uom": item.get("uom") or item.get("stock_uom") or "",
                "rate": float(item.get("rate") or 0),
                "amount": float(item.get("amount") or 0),
                "sales_order": item.get("sales_order") or sales_order_name,
                "warehouse": item.get("warehouse"),
            }
        )
    return rows


def _print_status(invoice_name):
    if not invoice_name:
        return ""
    return (
        frappe.db.get_value(
            "Cashier Print Queue",
            {"queue_key": "CASHIER|" + invoice_name},
            "status",
        )
        or ""
    )


def _bill_from_order(order):
    billing_status = str(order.get("custom_mobile_billing_status") or "Ordering").strip()
    if not billing_status:
        billing_status = "Ordering"

    invoice_name = str(order.get("custom_mobile_sales_invoice") or "").strip()
    source = order
    invoice_doc = None
    if invoice_name and frappe.db.exists("Sales Invoice", invoice_name):
        invoice_doc = frappe.get_doc("Sales Invoice", invoice_name)
        source = invoice_doc

    grand_total = float(source.get("grand_total") or 0)
    rounded_total = float(source.get("rounded_total") or 0)
    amount_due = rounded_total if rounded_total > 0 else grand_total

    return {
        "sales_order": order.name,
        "sales_invoice": invoice_name or None,
        "customer": order.customer,
        "customer_name": order.get("customer_name") or order.customer,
        "creation": str(source.get("creation") or order.creation or ""),
        "modified": str(order.modified or ""),
        "billing_status": billing_status,
        "payment_status": "Ready for Payment" if billing_status == "Bill Requested" else "Ordering",
        "print_status": _print_status(invoice_name),
        "can_pay": billing_status == "Bill Requested" and invoice_doc is not None and invoice_doc.docstatus == 0,
        "net_total": float(source.get("net_total") or 0),
        "total_taxes_and_charges": float(source.get("total_taxes_and_charges") or 0),
        "grand_total": grand_total,
        "outstanding_amount": amount_due,
        "currency": source.get("currency") or order.get("currency") or "",
        "docstatus": int(source.docstatus),
        "items": _item_rows(source, order.name),
        "taxes": _tax_rows(source),
    }


def _restaurant_customer_names():
    names = []
    for group_name in ("Dine In", "Takeaway"):
        rows = frappe.get_all(
            "Customer",
            filters={"customer_group": group_name, "disabled": 0},
            fields=["name"],
            limit_page_length=1000,
        )
        for row in rows:
            name = str(row.get("name") or "").strip()
            if name and name not in names:
                names.append(name)
    return names


def _active_bills():
    customers = _restaurant_customer_names()
    if not customers:
        return []

    names = []
    draft_rows = frappe.get_all(
        "Sales Order",
        filters={"docstatus": 0, "customer": ["in", customers]},
        fields=["name"],
        order_by="modified desc",
        limit_page_length=500,
    )
    for row in draft_rows:
        name = str(row.get("name") or "").strip()
        if name and name not in names:
            names.append(name)

    requested_rows = frappe.get_all(
        "Sales Order",
        filters={
            "docstatus": 1,
            "customer": ["in", customers],
            "custom_mobile_billing_status": "Bill Requested",
        },
        fields=["name"],
        order_by="modified desc",
        limit_page_length=500,
    )
    for row in requested_rows:
        name = str(row.get("name") or "").strip()
        if name and name not in names:
            names.append(name)

    bills = []
    for name in names:
        order = frappe.get_doc("Sales Order", name)
        status = str(order.get("custom_mobile_billing_status") or "Ordering").strip()
        if status in ("", "Ordering", "Bill Requested"):
            bills.append(_bill_from_order(order))
    return bills


def _payment_modes():
    modes = []
    rows = frappe.get_all(
        "Mode of Payment",
        filters={"enabled": 1},
        fields=["name"],
        order_by="name asc",
        limit_page_length=100,
    )
    for row in rows:
        name = str(row.get("name") or "").strip()
        if name:
            modes.append({"name": name, "default": name.lower() == "cash"})
    return modes


def _response(extra=None):
    message = {
        "bills": _active_bills(),
        "modes": _payment_modes(),
        "payment_entries": [],
        "change_amount": 0,
    }
    if extra:
        message.update(extra)
    frappe.response["message"] = message


def _pay(data):
    sales_order_name = str(data.get("sales_order") or "").strip()
    sales_invoice_name = str(data.get("sales_invoice") or "").strip()
    payments = data.get("payments")

    if isinstance(payments, str):
        payments = frappe.parse_json(payments)

    if not sales_order_name:
        frappe.throw("Sales Order is required.")
    if not sales_invoice_name:
        frappe.throw("Sales Invoice is required.")
    if not isinstance(payments, list) or not payments:
        frappe.throw("At least one payment is required.")

    order = frappe.get_doc("Sales Order", sales_order_name)
    billing_status = str(order.get("custom_mobile_billing_status") or "").strip()
    linked_invoice = str(order.get("custom_mobile_sales_invoice") or "").strip()

    if order.docstatus != 1:
        frappe.throw("Sales Order must be submitted before payment.")
    if linked_invoice != sales_invoice_name:
        frappe.throw("Sales Invoice does not match this Sales Order.")

    invoice = frappe.get_doc("Sales Invoice", sales_invoice_name)

    # Retry-safe terminal result after an uncertain client response.
    if billing_status == "Paid" and invoice.docstatus == 1:
        entries = _submitted_payment_entries(invoice.name)
        _response(
            {
                "payment_entries": entries,
                "payment_entry": entries[0] if entries else None,
                "change_amount": 0,
                "paid_sales_order": order.name,
                "paid_sales_invoice": invoice.name,
            }
        )
    else:
        if billing_status != "Bill Requested":
            frappe.throw("Payment is allowed only after Request for Bill.")
        if invoice.docstatus != 0:
            frappe.throw("The linked Sales Invoice must still be Draft.")

        due = float(invoice.get("rounded_total") or invoice.get("grand_total") or 0)
        if due <= 0:
            frappe.throw("Sales Invoice amount must be greater than zero.")

        normalized_payments = []
        total_tendered = 0.0
        non_cash_total = 0.0
        cash_total = 0.0

        for row in payments:
            mode_of_payment = str(row.get("mode_of_payment") or "").strip()
            amount = float(row.get("amount") or 0)
            if not mode_of_payment or amount <= 0:
                continue

            account = _mode_account(mode_of_payment, invoice.company)
            if not account:
                frappe.throw(
                    "Please configure a default account for Mode of Payment "
                    + mode_of_payment
                    + " in company "
                    + invoice.company
                    + "."
                )

            normalized_payments.append(
                {
                    "mode_of_payment": mode_of_payment,
                    "amount": amount,
                    "account": account,
                }
            )
            total_tendered += amount
            if mode_of_payment.lower() == "cash":
                cash_total += amount
            else:
                non_cash_total += amount

        if not normalized_payments:
            frappe.throw("No valid payment amount was supplied.")
        if total_tendered + 0.0001 < due:
            frappe.throw("Payment amount is less than the amount due.")
        if non_cash_total > due + 0.0001:
            frappe.throw("Non-cash payment cannot exceed the amount due.")
        if total_tendered > due + 0.0001 and cash_total <= 0:
            frappe.throw("Only Cash can include an amount returned as change.")

        change_amount = max(total_tendered - due, 0.0)

        # Stock impact happens only when the cashier accepts payment.
        invoice.update_stock = 1
        invoice.save(ignore_permissions=True)
        invoice.submit()

        remaining = due
        payment_entries = []
        for row in normalized_payments:
            if remaining <= 0.0001:
                break

            allocated = min(float(row.get("amount") or 0), remaining)
            if allocated <= 0:
                continue

            payment_entry = frappe.call(
                "erpnext.accounts.doctype.payment_entry.payment_entry.get_payment_entry",
                dt="Sales Invoice",
                dn=invoice.name,
                party_amount=allocated,
                bank_account=row.get("account"),
            )
            if isinstance(payment_entry, dict):
                payment_entry = frappe.get_doc(payment_entry)

            payment_entry.mode_of_payment = row.get("mode_of_payment")
            payment_entry.insert(ignore_permissions=True)
            payment_entry.submit()
            payment_entries.append(payment_entry.name)
            remaining -= allocated

        if remaining > 0.0001:
            frappe.throw("Payment could not be fully allocated to the Sales Invoice.")

        frappe.db.set_value(
            "Sales Order",
            order.name,
            "custom_mobile_billing_status",
            "Paid",
            update_modified=False,
        )

        _response(
            {
                "payment_entries": payment_entries,
                "payment_entry": payment_entries[0] if payment_entries else None,
                "change_amount": change_amount,
                "paid_sales_order": order.name,
                "paid_sales_invoice": invoice.name,
            }
        )


data = _request_data()
action = str(data.get("action") or "").strip()

if frappe.request.method == "POST" and action == "Pay":
    _pay(data)
elif frappe.request.method == "POST" and action:
    frappe.throw("Unsupported cashier action: " + action)
else:
    _response()
