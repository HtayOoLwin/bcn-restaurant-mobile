# Server Script API: bcn_print_job_result
# Deployment target: https://ourcity.s.frappe.cloud
#
# Printer client result contract:
# - requires BCN Printer Client role
# - only the claiming API user may report the result
# - Processing -> Printed/Failed is terminal
# - same-terminal retries are idempotent
# - opposite-terminal retries are conflicts

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

if "BCN Printer Client" not in roles:
    frappe.throw("BCN Printer Client role is required.")

if not frappe.db.exists("DocType", "BCN Print Job"):
    frappe.throw("BCN Print Job is not configured")

job_name = (frappe.form_dict.get("job_name") or "").strip()
requested_status = (frappe.form_dict.get("status") or "").strip()
error_message = frappe.form_dict.get("error_message") or ""

if not job_name:
    frappe.throw("job_name is required")

if requested_status not in ["Printed", "Failed"]:
    frappe.throw("Print result status must be Printed or Failed")

locked_rows = frappe.db.sql(
    "SELECT name FROM `tabBCN Print Job` WHERE name=%(name)s FOR UPDATE",
    {"name": job_name},
    as_dict=True,
)

if not locked_rows:
    frappe.throw("Print job not found: " + job_name)

job = frappe.get_doc("BCN Print Job", job_name)

if job.claimed_by != current_user:
    frappe.throw("Print job belongs to another printer client")

current_status = (job.status or "").strip()

if current_status == requested_status:
    frappe.response["message"] = {
        "job_name": job.name,
        "status": current_status,
        "duplicate": True,
    }
elif current_status == "Processing":
    if requested_status == "Printed":
        job.status = "Printed"
        job.printed_at = frappe.utils.now()
        job.error_message = ""
    else:
        job.status = "Failed"
        job.error_message = error_message

    job.save(ignore_permissions=True)

    frappe.response["message"] = {
        "job_name": job.name,
        "status": job.status,
        "duplicate": False,
    }
else:
    frappe.throw(
        "Print job result conflict: current status is "
        + current_status
        + ", requested status is "
        + requested_status
    )
