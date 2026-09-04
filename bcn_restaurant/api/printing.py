from __future__ import annotations

from uuid import UUID

import frappe

from bcn_restaurant.api.common import current_roles, get_settings, require_any_role
from local_printers.api.print_jobs import get_status, retry_failed
from local_printers.printing.jobs import create_print_job


def _require_authenticated() -> None:
    if frappe.session.user == "Guest":
        frappe.throw("Login required", frappe.AuthenticationError)


def _canonical_identifier(value: str, label: str) -> str:
    if not isinstance(value, str) or not value or value != value.strip() or len(value) > 140:
        frappe.throw(f"{label} must be a canonical identifier", frappe.ValidationError)
    if any(character in value for character in ("\n", "\r", "\t", "\0")):
        frappe.throw(f"{label} must be a canonical identifier", frappe.ValidationError)
    return value


def _canonical_job_id(job_id: str) -> str:
    job_id = _canonical_identifier(job_id, "job_id")
    try:
        parsed = UUID(job_id)
    except (AttributeError, ValueError):
        frappe.throw("job_id must be a canonical UUID", frappe.ValidationError)
    if str(parsed) != job_id.lower():
        frappe.throw("job_id must be a canonical UUID", frappe.ValidationError)
    return str(parsed)


def _cashier_configuration(pos_profile: str):
    configurations = frappe.get_all(
        "Printer Item Group",
        filters={
            "enabled": 1,
            "is_cashier": 1,
            "target_doctype": "Sales Invoice",
            "trigger_method": "manual",
            "pos_profile": pos_profile,
        },
        fields=["name", "printer", "print_format", "no_letterhead"],
        limit_page_length=2,
    )
    if not configurations:
        frappe.throw(
            f"No enabled cashier print configuration exists for POS Profile {pos_profile}",
            frappe.ValidationError,
        )
    if len(configurations) != 1:
        frappe.throw(
            f"More than one enabled cashier print configuration exists for POS Profile {pos_profile}",
            frappe.ValidationError,
        )

    configuration = configurations[0]
    if not configuration.printer:
        frappe.throw(
            f"Cashier print configuration {configuration.name} is incomplete",
            frappe.ValidationError,
        )
    return configuration


def _lock_invoice_for_cashier_job(invoice_name: str) -> None:
    rows = frappe.db.sql(
        """
        SELECT name
        FROM `tabSales Invoice`
        WHERE name = %(invoice_name)s
        FOR UPDATE
        """,
        {"invoice_name": invoice_name},
        as_dict=True,
    )
    if not rows:
        frappe.throw("Unknown Sales Invoice", frappe.ValidationError)


def _has_prior_cashier_job(invoice_name: str) -> bool:
    rows = frappe.db.sql(
        """
        SELECT name
        FROM `tabLocal Print Job`
        WHERE source_doctype = %(source_doctype)s
            AND source_name = %(source_name)s
            AND ticket_type = %(ticket_type)s
        ORDER BY creation ASC, name ASC
        LIMIT 1
        FOR UPDATE
        """,
        {
            "source_doctype": "Sales Invoice",
            "source_name": invoice_name,
            "ticket_type": "Cashier",
        },
        as_dict=True,
    )
    return bool(rows)


def _publish_job_wake(job_id: str, pos_profile: str) -> None:
    metadata = {
        "job_id": job_id,
        "pos_profile": pos_profile,
        "ticket_type": "Cashier",
    }
    try:
        frappe.publish_realtime("document_print_event", metadata, after_commit=True)
    except Exception:
        frappe.log_error(
            f"Could not publish wake metadata for Local Print Job {job_id}",
            title="Local print wake failed",
        )


@frappe.whitelist(methods=["POST"])
def request_cashier_bill(invoice_name: str) -> dict[str, str | bool]:
    _require_authenticated()
    require_any_role("Cashier", "Restaurant Manager")
    invoice_name = _canonical_identifier(invoice_name, "invoice_name")
    settings = get_settings()

    invoice = frappe.get_doc("Sales Invoice", invoice_name)
    if not frappe.has_permission("Sales Invoice", ptype="read", doc=invoice):
        frappe.throw("You are not permitted to read this Sales Invoice", frappe.PermissionError)
    if invoice.docstatus != 1:
        frappe.throw("Cashier bills may be printed only for submitted Sales Invoices")
    if invoice.pos_profile != settings["pos_profile"]:
        frappe.throw(
            "Sales Invoice is outside the current POS Profile",
            frappe.PermissionError,
        )
    roles = set(current_roles())
    if not roles.intersection({"Administrator", "System Manager"}) and not frappe.has_permission(
        "POS Profile",
        ptype="read",
        doc=settings["pos_profile"],
    ):
        frappe.throw("You cannot use the current POS Profile", frappe.PermissionError)

    configuration = _cashier_configuration(settings["pos_profile"])
    payload = frappe.get_print(
        "Sales Invoice",
        invoice.name,
        print_format=configuration.print_format,
        as_pdf=True,
        no_letterhead=int(configuration.no_letterhead or 0),
    )
    # The source row is a stable serialization point even when no prior job
    # exists yet. Locking/current reads avoid a stale REPEATABLE READ snapshot.
    _lock_invoice_for_cashier_job(invoice.name)
    is_reprint = _has_prior_cashier_job(invoice.name)
    job = create_print_job(
        source_doc=invoice,
        printer=configuration.printer,
        ticket_type="Cashier",
        print_format=configuration.print_format,
        payload=payload,
        no_letterhead=bool(configuration.no_letterhead),
    )
    _publish_job_wake(job.job_id, settings["pos_profile"])
    return {
        "job_id": job.job_id,
        "status": job.status,
        "is_reprint": is_reprint,
    }


@frappe.whitelist()
def get_print_status() -> dict[str, bool | int | str | None]:
    _require_authenticated()
    require_any_role("Cashier", "Restaurant Manager")
    settings = get_settings()
    status = get_status(pos_profile=settings["pos_profile"])
    return {
        "online": bool(status["online"]),
        "last_seen": status.get("last_seen"),
        "pending": int(status["pending"]),
        "failed": int(status["failed"]),
    }


@frappe.whitelist(methods=["POST"])
def retry_print_job(job_id: str) -> dict[str, str]:
    _require_authenticated()
    require_any_role("Restaurant Manager")
    job_id = _canonical_job_id(job_id)
    result = retry_failed(job_id=job_id)
    return {"status": result["status"]}
