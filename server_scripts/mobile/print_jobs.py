# Server Script API: bcn_print_jobs
# Deployment target: https://ourcity.s.frappe.cloud
#
# Printer client polling contract:
# - requires BCN Printer Client role
# - stale Processing jobs older than 60 seconds become Failed/unknown
# - stale jobs are never automatically requeued
# - one poll claims at most one oldest matching Pending job

current_user = frappe.session.user
if not current_user or current_user == "Guest":
    frappe.throw("Authentication is required.")

role_rows = frappe.get_all(
    "Has Role",
    filters={"parent": current_user, "parenttype": "User"},
    fields=["role"],
    limit_page_length=200,
)
roles = []
for role_row in role_rows:
    if role_row.role and role_row.role not in roles:
        roles.append(role_row.role)

if "BCN Printer Client" not in roles:
    frappe.throw("BCN Printer Client role is required.")
if not frappe.db.exists("DocType", "BCN Print Job"):
    frappe.throw("BCN Print Job is not configured")

raw_printers = frappe.form_dict.get("printers")
if isinstance(raw_printers, str):
    printers_input = json.loads(raw_printers) if raw_printers else []
elif isinstance(raw_printers, (list, tuple)):
    printers_input = raw_printers
else:
    printers_input = []

printers = []
for value in printers_input:
    printer_name = str(value or "").strip()
    if printer_name and printer_name not in printers:
        printers.append(printer_name)
if not printers:
    frappe.throw("At least one printer name is required.")

cutoff = frappe.utils.add_to_date(frappe.utils.now_datetime(), seconds=-60)
stale_rows = frappe.get_all(
    "BCN Print Job",
    filters={"status": "Processing", "printer_name": ["in", printers], "claimed_at": ["<", cutoff]},
    fields=["name"], order_by="claimed_at asc", limit_page_length=500,
)
for stale_row in stale_rows:
    locked_stale = frappe.db.sql(
        "SELECT name FROM `tabBCN Print Job` WHERE name=%(name)s FOR UPDATE",
        {"name": stale_row.name}, as_dict=True,
    )
    if locked_stale:
        stale_job = frappe.get_doc("BCN Print Job", stale_row.name)
        if stale_job.status == "Processing" and stale_job.claimed_at and stale_job.claimed_at < cutoff:
            stale_job.status = "Failed"
            stale_job.error_message = "Print result unknown after client timeout"
            stale_job.save(ignore_permissions=True)

pending_rows = frappe.get_all(
    "BCN Print Job",
    filters={"status": "Pending", "printer_name": ["in", printers]},
    fields=["name"], order_by="creation asc", limit_page_length=1,
)
if not pending_rows:
    frappe.response["message"] = {"job": None}
else:
    candidate_name = pending_rows[0].name
    locked_rows = frappe.db.sql(
        "SELECT name FROM `tabBCN Print Job` WHERE name=%(name)s FOR UPDATE",
        {"name": candidate_name}, as_dict=True,
    )
    if not locked_rows:
        frappe.response["message"] = {"job": None}
    else:
        job = frappe.get_doc("BCN Print Job", candidate_name)
        if job.status != "Pending" or job.printer_name not in printers:
            frappe.response["message"] = {"job": None}
        else:
            job.status = "Processing"
            job.claimed_by = current_user
            job.claimed_at = frappe.utils.now()
            job.attempt_count = int(job.attempt_count or 0) + 1
            job.save(ignore_permissions=True)
            frappe.response["message"] = {
                "job": {
                    "name": job.name,
                    "request_id": job.request_id,
                    "document_type": job.document_type,
                    "document_name": job.document_name,
                    "printer_name": job.printer_name,
                    "print_format": job.print_format,
                    "render_mode": (job.get("render_mode") or "PDF"),
                    "html_content": job.get("html_content") or "",
                    "pdf_base64": job.pdf_base64,
                    "attempt_count": int(job.attempt_count or 0),
                }
            }
