# Server Script
# Script Type: API
# API Method: bcn_request_for_bill
# Allow Guest: No


data = frappe.request.get_json(silent=True)
if not data:
    data = frappe.form_dict

sales_order_name = str(data.get("sales_order") or "").strip()
if not sales_order_name:
    frappe.throw("Sales Order is required.")

if not frappe.db.exists("Sales Order", sales_order_name):
    frappe.throw("Sales Order was not found.")

sales_order = frappe.get_doc("Sales Order", sales_order_name)
billing_status = str(sales_order.get("custom_mobile_billing_status") or "Ordering").strip()
linked_invoice = str(sales_order.get("custom_mobile_sales_invoice") or "").strip()

if billing_status == "Paid":
    frappe.throw("This order has already been paid.")

# Retry-safe return. A client timeout after a successful request must not
# submit the Sales Order twice, create another Sales Invoice, or duplicate
# the durable print queue row.
if billing_status == "Bill Requested" and linked_invoice:
    if not frappe.db.exists("Sales Invoice", linked_invoice):
        frappe.throw("The linked Sales Invoice no longer exists.")

    queue_key = "CASHIER|" + linked_invoice
    if not frappe.db.exists("Cashier Print Queue", {"queue_key": queue_key}):
        printer_name = str(
            frappe.db.get_single_value("Cashier Print Settings", "printer_name") or ""
        ).strip()
        enabled = frappe.db.get_single_value("Cashier Print Settings", "enabled")
        if enabled in (0, "0", False) or not printer_name:
            frappe.throw("Cashier printer is not configured.")

        queue = frappe.get_doc(
            {
                "doctype": "Cashier Print Queue",
                "sales_invoice": linked_invoice,
                "sales_order": sales_order.name,
                "printer_name": printer_name,
                "status": "Pending",
                "retry_count": 0,
                "queue_key": queue_key,
            }
        )
        queue.insert(ignore_permissions=True)

    frappe.response["message"] = {
        "sales_order": sales_order.name,
        "sales_invoice": linked_invoice,
        "billing_status": "Bill Requested",
        "print_status": frappe.db.get_value(
            "Cashier Print Queue", {"queue_key": queue_key}, "status"
        )
        or "Pending",
        "duplicate": True,
    }
else:
    if sales_order.docstatus != 0:
        frappe.throw("Only a Draft Sales Order can request a bill.")

    if billing_status not in ("", "Ordering"):
        frappe.throw("This order is not in Ordering status.")

    if not sales_order.items:
        frappe.throw("Cannot request a bill for an empty order.")

    printer_name = str(
        frappe.db.get_single_value("Cashier Print Settings", "printer_name") or ""
    ).strip()
    enabled = frappe.db.get_single_value("Cashier Print Settings", "enabled")
    if enabled in (0, "0", False) or not printer_name:
        frappe.throw("Cashier printer is not configured.")

    # Set the lock state before submit. The whole API request stays in the
    # normal Frappe transaction, so any later exception rolls this back.
    sales_order.custom_mobile_billing_status = "Bill Requested"
    sales_order.custom_bill_requested_at = frappe.utils.now()
    sales_order.custom_bill_requested_by = frappe.session.user
    sales_order.save(ignore_permissions=True)
    sales_order.submit()

    # ERPNext v16 standard Sales Order -> Sales Invoice mapper.
    sales_invoice = frappe.call(
        "erpnext.selling.doctype.sales_order.sales_order.make_sales_invoice",
        source_name=sales_order.name,
        ignore_permissions=True,
    )
    if not sales_invoice:
        frappe.throw("ERPNext could not create the Sales Invoice.")

    if isinstance(sales_invoice, dict):
        sales_invoice = frappe.get_doc(sales_invoice)

    # Bill is intentionally printed while Sales Invoice is still Draft.
    sales_invoice.insert(ignore_permissions=True)

    frappe.db.set_value(
        "Sales Order",
        sales_order.name,
        "custom_mobile_sales_invoice",
        sales_invoice.name,
        update_modified=False,
    )

    queue_key = "CASHIER|" + sales_invoice.name
    if not frappe.db.exists("Cashier Print Queue", {"queue_key": queue_key}):
        queue = frappe.get_doc(
            {
                "doctype": "Cashier Print Queue",
                "sales_invoice": sales_invoice.name,
                "sales_order": sales_order.name,
                "printer_name": printer_name,
                "status": "Pending",
                "retry_count": 0,
                "queue_key": queue_key,
            }
        )
        queue.insert(ignore_permissions=True)

    frappe.response["message"] = {
        "sales_order": sales_order.name,
        "sales_invoice": sales_invoice.name,
        "billing_status": "Bill Requested",
        "print_status": "Pending",
        "duplicate": False,
    }
