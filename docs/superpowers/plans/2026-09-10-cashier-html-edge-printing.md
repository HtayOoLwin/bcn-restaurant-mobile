# Cashier HTML + Edge Printing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make mobile cashier Sales Invoice receipts print with correct Myanmar shaping and 80mm spacing by storing a rendered HTML snapshot in `BCN Print Job` and rendering it locally with Microsoft Edge on the Windows printer client, while preserving old PDF jobs and waiter kitchen printing.

**Architecture:** Frappe keeps owning Sales Invoice/Jinja rendering, but new cashier jobs call `frappe.get_print(..., as_pdf=False)` so the server stores the browser-style HTML instead of a wkhtmltopdf PDF. `bcn_print_jobs` sends the snapshot plus `render_mode`; the Windows client treats missing/`PDF` mode exactly as before and renders `HTML` mode through a dedicated Edge helper before sending the resulting PDF through the existing Sumatra print function. Closed-order reprints copy the stored snapshot instead of re-rendering.

**Tech Stack:** ERPNext/Frappe v16 Server Script API, Python 3.10+, requests, Microsoft Edge headless, SumatraPDF, pytest, PowerShell.

**Spec:** `docs/superpowers/specs/2026-09-10-cashier-html-edge-printing-design.md`

## Global Constraints

- Production target is `https://ourcity.s.frappe.cloud`.
- Company is `Doh Myot Daw BBQ & Restaurant`; POS Profile is `DMT`; currency is `MMK`.
- Live OurCity uses Server Scripts; GitHub mirror changes do **not** deploy automatically.
- Do not change payment logic, order lifecycle semantics, or waiter kitchen queue behavior.
- `queue_worker.py` must remain unchanged.
- Keep existing `pdf_base64` support for old jobs; missing `render_mode` means `PDF`.
- New cashier jobs use `render_mode = "HTML"` and `html_content`; do not silently fall back to wkhtmltopdf when Edge rendering fails.
- No font files are added, bundled, or distributed. Myanmar rendering relies on Windows/Edge local fonts.
- Frappe Server Scripts must avoid Python sequence unpacking because Safe Exec can raise `_unpack_sequence_`; use dict/index access instead.
- Use test-first development and fresh verification before declaring success.

---

## File Structure

### `HtayOoLwin/local_printers_winapp` — branch `feature/kitchen-print-queue-polling`

- Create `cashier_html.py` — cashier-only UTF-8 Edge HTML-to-PDF renderer. Keep this separate from `kitchen_ticket.py` so the proven waiter path is not refactored during this change.
- Create `tests/test_cashier_html.py` — renderer timing, UTF-8/Myanmar preservation, and Edge failure tests.
- Modify `printer_handlers.py` — dispatch `PDF` versus `HTML` jobs and route both through existing `print_pdf_silent()`.
- Modify `tests/test_printer_handlers.py` — PDF backward compatibility, HTML path, missing HTML, invalid mode.
- Modify `tests/test_polling_client.py` — prove an HTML job reaches `print_single_job()` unchanged and Edge/print exceptions become a `Failed` result.
- Modify `README.md` — describe dual-mode cashier polling and `EDGE_PATH` requirement for HTML jobs.
- Modify `tests/test_cashier_polling_docs.py` — enforce documentation/config contract.
- Do not modify `queue_worker.py` or `kitchen_ticket.py`.

### `HtayOoLwin/bcn-restaurant-mobile` — branch `bcn-restaurant-mobile-without-kitchen-monitor`

- Modify `server_scripts/mobile/request_for_bill.py` — create first cashier job from HTML snapshot.
- Modify `server_scripts/mobile/cashier_print_bill.py` — Billing reprint creates fresh HTML snapshot; Closed reprint copies stored HTML/PDF mode and payload.
- Modify `server_scripts/mobile/print_jobs.py` — include `render_mode` and `html_content` in claimed job response while preserving `pdf_base64`.
- Modify `tests/test_ourcity_server_script_contract.py` — server-script HTML-mode and compatibility assertions.
- Modify `tests/test_request_for_bill_merge_contract.py` — Request for Bill contract moves from PDF to HTML snapshot.
- Modify `docs/server-script-mobile.md` — document `BCN Print Job.render_mode`, `html_content`, deployment order, and local Edge rendering.

---

### Task 1: Add the cashier-only Edge renderer on Windows

**Files:**
- Create: `cashier_html.py`
- Create: `tests/test_cashier_html.py`

**Interfaces:**
- Consumes: rendered HTML string and configured Edge executable path.
- Produces: `render_html_to_pdf_edge(html: str, edge_path: str, timeout_seconds: float = 15.0) -> str`, returning a non-empty local PDF path or raising an exception.

- [ ] **Step 1: Write failing renderer tests**

Create `tests/test_cashier_html.py` with these behaviors:

```python
import os
import subprocess
import threading
import time
from pathlib import Path

import pytest

import cashier_html


def test_edge_renderer_writes_utf8_html_and_waits_for_nonempty_pdf(tmp_path, monkeypatch):
    edge = tmp_path / "msedge.exe"
    edge.write_text("edge", encoding="utf-8")
    seen = {}
    writers = []

    def fake_run(command, check):
        html_uri = command[-1]
        html_path = Path(html_uri.removeprefix("file:///"))
        if os.name == "nt":
            html_path = Path(str(html_path).replace("/", "\\"))
        seen["html"] = html_path.read_text(encoding="utf-8")

        pdf_arg = next(x for x in command if x.startswith("--print-to-pdf="))
        pdf_path = pdf_arg.split("=", 1)[1]

        def delayed_write():
            time.sleep(0.08)
            Path(pdf_path).write_bytes(b"%PDF-cashier-edge")

        thread = threading.Thread(target=delayed_write)
        thread.start()
        writers.append(thread)

    monkeypatch.setattr(subprocess, "run", fake_run)

    html = "<html><meta charset='utf-8'><body>မြန်မာ စမ်းသပ်</body></html>"
    pdf_path = cashier_html.render_html_to_pdf_edge(
        html, str(edge), timeout_seconds=2
    )

    for thread in writers:
        thread.join()

    assert "မြန်မာ စမ်းသပ်" in seen["html"]
    assert Path(pdf_path).read_bytes() == b"%PDF-cashier-edge"


def test_edge_renderer_rejects_empty_html(tmp_path):
    with pytest.raises(ValueError, match="Cashier HTML is empty"):
        cashier_html.render_html_to_pdf_edge("   ", str(tmp_path / "msedge.exe"))


def test_edge_renderer_raises_when_pdf_never_appears(tmp_path, monkeypatch):
    edge = tmp_path / "msedge.exe"
    edge.write_text("edge", encoding="utf-8")
    monkeypatch.setattr(subprocess, "run", lambda command, check: None)

    with pytest.raises(RuntimeError, match="Microsoft Edge did not create the cashier PDF"):
        cashier_html.render_html_to_pdf_edge(
            "<html><body>bill</body></html>",
            str(edge),
            timeout_seconds=0.05,
        )
```

- [ ] **Step 2: Run only the new tests and verify RED**

Run on Windows:

```powershell
cd C:\Users\htayoolwin\local_printers_winapp_code
.\.venv\Scripts\python.exe -m pytest tests\test_cashier_html.py -q
```

Expected: collection/import failure because `cashier_html.py` does not exist yet.

- [ ] **Step 3: Implement the dedicated renderer**

Create `cashier_html.py` using the already-proven kitchen Edge pattern, without importing or changing `kitchen_ticket.py`:

```python
from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import time
from pathlib import Path


def render_html_to_pdf_edge(
    html: str,
    edge_path: str,
    timeout_seconds: float = 15.0,
) -> str:
    if not str(html or "").strip():
        raise ValueError("Cashier HTML is empty")

    edge_path = str(edge_path or "").strip()
    if not edge_path:
        raise ValueError("EDGE_PATH is required for HTML cashier printing")

    work_dir = tempfile.mkdtemp(prefix="cashier_edge_")
    html_path = os.path.join(work_dir, "bill.html")
    pdf_path = os.path.join(work_dir, "bill.pdf")
    profile_dir = os.path.join(work_dir, "profile")

    with open(html_path, "w", encoding="utf-8") as fh:
        fh.write(html)

    command = [
        edge_path,
        "--headless",
        "--disable-gpu",
        "--no-pdf-header-footer",
        f"--user-data-dir={profile_dir}",
        f"--print-to-pdf={pdf_path}",
        Path(html_path).resolve().as_uri(),
    ]

    try:
        subprocess.run(command, check=True)
        deadline = time.monotonic() + float(timeout_seconds)
        while time.monotonic() < deadline:
            if os.path.exists(pdf_path) and os.path.getsize(pdf_path) > 0:
                return pdf_path
            time.sleep(0.05)
    except Exception:
        shutil.rmtree(work_dir, ignore_errors=True)
        raise

    shutil.rmtree(work_dir, ignore_errors=True)
    raise RuntimeError(
        "Microsoft Edge did not create the cashier PDF before timeout"
    )
```

- [ ] **Step 4: Run the renderer tests and verify GREEN**

```powershell
.\.venv\Scripts\python.exe -m pytest tests\test_cashier_html.py -q
```

Expected: all tests pass.

- [ ] **Step 5: Commit Task 1 in the Windows repo**

```powershell
git add cashier_html.py tests\test_cashier_html.py
git commit -m "feat: add cashier Edge HTML renderer"
```

---

### Task 2: Make the Windows print handler dual-mode without breaking PDF jobs

**Files:**
- Modify: `printer_handlers.py`
- Modify: `tests/test_printer_handlers.py`

**Interfaces:**
- Consumes: job dict containing `render_mode`, `html_content`, `pdf_base64`, `printer_name`; config containing `EDGE_PATH` and `SUMATRA_PDF_PATH`.
- Produces: existing `print_single_job(job, config_data) -> str` contract; missing `render_mode` remains PDF.

- [ ] **Step 1: Add failing tests for dual-mode dispatch**

Append tests that require:

```python
def test_print_single_job_missing_render_mode_keeps_pdf_path(monkeypatch, tmp_path):
    # Existing PDF behavior remains valid when render_mode is absent.
    ...


def test_print_single_job_html_mode_renders_edge_then_prints(monkeypatch, tmp_path):
    rendered = tmp_path / "cashier.pdf"
    rendered.write_bytes(b"%PDF-edge")
    calls = []
    monkeypatch.setattr(
        printer_handlers,
        "render_html_to_pdf_edge",
        lambda html, edge: calls.append(("render", html, edge)) or str(rendered),
    )
    monkeypatch.setattr(
        printer_handlers,
        "print_pdf_silent",
        lambda pdf, printer, path, **kwargs: calls.append(
            ("print", pdf, printer, path, kwargs)
        ),
    )

    result = printer_handlers.print_single_job(
        {
            "render_mode": "HTML",
            "html_content": "<html><body>မြန်မာ</body></html>",
            "printer_name": "Kitchen Printer",
        },
        {
            "EDGE_PATH": r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
            "SUMATRA_PDF_PATH": "SumatraPDF.exe",
        },
    )

    assert result == "Kitchen Printer"
    assert calls[0][0] == "render"
    assert calls[1][0] == "print"


def test_print_single_job_html_mode_requires_html_content():
    with pytest.raises(ValueError, match="HTML print job has no html_content"):
        printer_handlers.print_single_job(
            {"render_mode": "HTML", "printer_name": "Kitchen Printer"},
            {"EDGE_PATH": "msedge.exe", "SUMATRA_PDF_PATH": "SumatraPDF.exe"},
        )


def test_print_single_job_rejects_unknown_render_mode():
    with pytest.raises(ValueError, match="Unsupported print render_mode"):
        printer_handlers.print_single_job(
            {"render_mode": "RAW", "printer_name": "Kitchen Printer"},
            {},
        )
```

Replace the `...` in the actual test with the same explicit `save_pdf_from_base64` and `print_pdf_silent` assertions already used by the existing success test; do not leave placeholders in committed code.

- [ ] **Step 2: Run targeted tests and verify RED**

```powershell
.\.venv\Scripts\python.exe -m pytest tests\test_printer_handlers.py -q
```

Expected: HTML-mode tests fail because `printer_handlers` does not yet dispatch by `render_mode`.

- [ ] **Step 3: Implement minimal dual-mode dispatch**

At module top:

```python
from cashier_html import render_html_to_pdf_edge
```

Refactor only `print_single_job()` so the mode selection is explicit:

```python
render_mode = str(job.get("render_mode") or "PDF").strip().upper()
printer_name = job.get("printer_name") or job.get("printer")
if not printer_name:
    raise ValueError("Print job has no printer name")

if render_mode == "HTML":
    html_content = str(job.get("html_content") or "")
    if not html_content.strip():
        raise ValueError("HTML print job has no html_content")
    edge_path = str(config_data.get("EDGE_PATH") or "").strip()
    if not edge_path:
        raise ValueError("EDGE_PATH is required for HTML cashier printing")
    pdf_path = render_html_to_pdf_edge(html_content, edge_path)
elif render_mode == "PDF":
    pdf_base64 = job.get("pdf_base64")
    if not pdf_base64:
        raise ValueError("Print job has no pdf_base64")
    pdf_path = save_pdf_from_base64(pdf_base64)
    if not pdf_path:
        raise ValueError("Failed to decode/save print job PDF")
else:
    raise ValueError("Unsupported print render_mode: " + render_mode)
```

Keep the existing common Sumatra block unchanged after `pdf_path` is resolved. Do not change `print_pdf_silent()` or its `noscale` setting in this task.

- [ ] **Step 4: Run handler tests and full Windows tests**

```powershell
.\.venv\Scripts\python.exe -m pytest tests\test_printer_handlers.py tests\test_cashier_html.py -q
.\.venv\Scripts\python.exe -m pytest tests -q
```

Expected: both targeted and full suite pass.

- [ ] **Step 5: Commit Task 2 in the Windows repo**

```powershell
git add printer_handlers.py tests\test_printer_handlers.py
git commit -m "feat: print cashier HTML jobs through Edge"
```

---

### Task 3: Prove polling passes HTML jobs unchanged and reports Edge failures

**Files:**
- Modify: `tests/test_polling_client.py`
- Production file `polling_client.py`: no change expected unless the tests expose a contract bug.

**Interfaces:**
- Consumes: claimed job dict returned by `bcn_print_jobs`.
- Produces: `PendingResult(job_name, "Printed"|"Failed", error_message)` exactly once per physical attempt.

- [ ] **Step 1: Add the HTML pass-through and failure tests**

Add:

```python
def test_process_claimed_html_job_passes_snapshot_unchanged(monkeypatch):
    polling_client = _module()
    seen = []
    job = {
        "name": "BCN-PRINT-JOB-HTML-00001",
        "printer_name": "Kitchen Printer",
        "render_mode": "HTML",
        "html_content": "<html><body>မြန်မာ</body></html>",
        "pdf_base64": "",
    }
    monkeypatch.setattr(
        polling_client,
        "print_single_job",
        lambda value, cfg: seen.append(value.copy()) or "Kitchen Printer",
    )

    result = polling_client.process_claimed_job(job, _cfg())

    assert seen == [job]
    assert result == polling_client.PendingResult(
        "BCN-PRINT-JOB-HTML-00001", "Printed", ""
    )


def test_process_claimed_html_job_reports_edge_failure(monkeypatch):
    polling_client = _module()
    monkeypatch.setattr(
        polling_client,
        "print_single_job",
        lambda job, cfg: (_ for _ in ()).throw(
            RuntimeError("Microsoft Edge did not create the cashier PDF before timeout")
        ),
    )

    result = polling_client.process_claimed_job(
        {
            "name": "BCN-PRINT-JOB-HTML-00002",
            "printer_name": "Kitchen Printer",
            "render_mode": "HTML",
            "html_content": "<html><body>bill</body></html>",
        },
        _cfg(),
    )

    assert result.status == "Failed"
    assert "Microsoft Edge did not create the cashier PDF" in result.error_message
```

- [ ] **Step 2: Run the tests**

```powershell
.\.venv\Scripts\python.exe -m pytest tests\test_polling_client.py -q
```

Expected: they should pass without production change because `process_claimed_job()` already passes the whole job dict to `print_single_job()` and captures exceptions. If they fail, make only the smallest production change needed and rerun RED/GREEN before committing.

- [ ] **Step 3: Commit the contract tests**

```powershell
git add tests\test_polling_client.py
git commit -m "test: cover cashier HTML polling contract"
```

---

### Task 4: Update Windows documentation before server begins producing HTML jobs

**Files:**
- Modify: `README.md`
- Modify: `tests/test_cashier_polling_docs.py`

**Interfaces:**
- Documents that `EDGE_PATH` is required only for HTML cashier jobs and that PDF jobs remain supported.

- [ ] **Step 1: Add failing documentation assertions**

Extend `test_cashier_polling_docs.py` with exact expectations:

```python
assert "EDGE_PATH" in cfg
assert "render_mode" in source
assert "HTML" in source
assert "pdf_base64" in source
assert "Microsoft Edge" in source
```

- [ ] **Step 2: Run and verify RED**

```powershell
.\.venv\Scripts\python.exe -m pytest tests\test_cashier_polling_docs.py -q
```

Expected: README-specific assertions fail until dual-mode flow is documented.

- [ ] **Step 3: Update README**

Change the Cashier section to show:

```text
New cashier job:
Draft Sales Invoice -> HTML snapshot -> BCN Print Job render_mode=HTML
-> socket_app.py -> Edge headless -> local PDF -> Sumatra -> printer

Old job:
pdf_base64 -> local PDF -> Sumatra -> printer
```

State explicitly that `EDGE_PATH` must point to the installed Microsoft Edge executable for HTML cashier jobs and that `queue_worker.py` remains a separate waiter-kitchen process.

- [ ] **Step 4: Run docs test and compile checks**

```powershell
.\.venv\Scripts\python.exe -m pytest tests\test_cashier_polling_docs.py -q
.\.venv\Scripts\python.exe -m py_compile cashier_html.py polling_client.py printer_handlers.py socket_app.py
```

Expected: pass.

- [ ] **Step 5: Commit Task 4**

```powershell
git add README.md tests\test_cashier_polling_docs.py
git commit -m "docs: describe dual-mode cashier printing"
```

At this checkpoint the Windows app is safe to deploy first: it accepts both the old PDF contract and the future HTML contract.

---

### Task 5: Change Request for Bill from server PDF snapshot to HTML snapshot

**Files:**
- Modify: `tests/test_ourcity_server_script_contract.py`
- Modify: `tests/test_request_for_bill_merge_contract.py`
- Modify: `server_scripts/mobile/request_for_bill.py`

**Interfaces:**
- Consumes: `DMT.custom_cashier_invoice_print_format` and the created Draft Sales Invoice.
- Produces: a Pending `BCN Print Job` with `render_mode = "HTML"`, `html_content` from `frappe.get_print(..., as_pdf=False)`, and the same deterministic `request_id = "bill-request|" + sales_order.name`.

- [ ] **Step 1: Change tests first**

Update the old PDF assertions so Request for Bill now requires all of these strings:

```python
assert "render_sales_invoice_html" in source
assert "as_pdf=False" in source
assert 'job.render_mode = "HTML"' in source
assert "job.html_content = rendered[\"html_content\"]" in source
assert 'request_id = "bill-request|" + sales_order.name' in source
assert "encode_pdf_base64" not in source
assert "as_pdf=True" not in source
```

Keep the existing assertions for Sales Order submit, Draft Sales Invoice creation, `update_stock = 1`, Pending status, duplicate retry behavior, and no explicit commit/rollback.

- [ ] **Step 2: Run targeted server contract tests and verify RED**

From `C:\Users\htayoolwin\bcn-restaurant-mobile`:

```powershell
python -m pytest tests\test_ourcity_server_script_contract.py tests\test_request_for_bill_merge_contract.py -q
```

Expected: Request-for-Bill HTML assertions fail against the current PDF implementation.

- [ ] **Step 3: Replace the PDF helper with a Safe-Exec-friendly HTML helper**

Use this shape in `request_for_bill.py`:

```python
def render_sales_invoice_html(profile, sales_invoice):
    invoice_print_format = (
        profile.get("custom_cashier_invoice_print_format") or ""
    ).strip()
    if not invoice_print_format:
        frappe.throw("DMT custom_cashier_invoice_print_format is required")

    print_format_row = frappe.db.get_value(
        "Print Format",
        invoice_print_format,
        ["name", "doc_type", "disabled"],
        as_dict=True,
    )
    if not print_format_row:
        frappe.throw(
            "Cashier Sales Invoice print format not found: "
            + invoice_print_format
        )
    if print_format_row.disabled:
        frappe.throw(
            "Cashier Sales Invoice print format is disabled: "
            + invoice_print_format
        )
    if print_format_row.doc_type != "Sales Invoice":
        frappe.throw("Cashier Sales Invoice print format must be for Sales Invoice")

    html_content = frappe.get_print(
        "Sales Invoice",
        sales_invoice.name,
        print_format=invoice_print_format,
        as_pdf=False,
    )
    if not html_content:
        frappe.throw("Cashier HTML snapshot could not be rendered")

    return {
        "html_content": html_content,
        "print_format": invoice_print_format,
    }
```

`frappe.get_print(..., as_pdf=False)` uses Frappe's printview HTML path, avoiding wkhtmltopdf while retaining the Jinja Print Format. Do not use `pdf, print_format = ...` or any other sequence unpacking.

In `ensure_print_job()`:

```python
rendered = render_sales_invoice_html(profile, sales_invoice)
job = frappe.new_doc("BCN Print Job")
job.request_id = request_id
job.document_type = "Sales Order"
job.document_name = sales_order.name
job.printer_name = printer_name
job.print_format = rendered["print_format"]
job.render_mode = "HTML"
job.html_content = rendered["html_content"]
job.status = "Pending"
job.attempt_count = 0
job.requested_by = current_user
job.requested_at = frappe.utils.now()
job.insert(ignore_permissions=True)
```

Remove the PDF encoder and all new-job `pdf_base64` generation from this script. Existing deterministic duplicate lookup remains unchanged.

- [ ] **Step 4: Run targeted tests and verify GREEN**

```powershell
python -m pytest tests\test_ourcity_server_script_contract.py tests\test_request_for_bill_merge_contract.py -q
```

Expected: pass.

- [ ] **Step 5: Commit Task 5 in the mobile repo**

```powershell
git add server_scripts\mobile\request_for_bill.py tests\test_ourcity_server_script_contract.py tests\test_request_for_bill_merge_contract.py
git commit -m "feat: queue cashier bill HTML snapshots"
```

---

### Task 6: Make cashier reprint preserve HTML or legacy PDF snapshots

**Files:**
- Modify: `tests/test_ourcity_server_script_contract.py`
- Modify: `server_scripts/mobile/cashier_print_bill.py`

**Interfaces:**
- Billing order: render a fresh current Draft Sales Invoice HTML snapshot.
- Closed order: copy latest stored mode and corresponding payload; do not re-render.

- [ ] **Step 1: Add failing reprint contract assertions**

Require the source to contain:

```python
assert "render_invoice_html" in source
assert "as_pdf=False" in source
assert 'job.render_mode = "HTML"' in source
assert "job.html_content" in source
assert 'previous_mode = (previous_job.get("render_mode") or "PDF").strip().upper()' in source
assert 'if previous_mode == "HTML":' in source
assert "previous_job.html_content" in source
assert "previous_job.pdf_base64" in source
assert 'job.render_mode = "PDF"' in source
```

Also retain existing request-id serialization/idempotency and `Open` rejection assertions.

- [ ] **Step 2: Run and verify RED**

```powershell
python -m pytest tests\test_ourcity_server_script_contract.py -q
```

Expected: reprint HTML compatibility assertions fail.

- [ ] **Step 3: Implement Billing fresh HTML mode**

Use the same validation/rendering logic as Task 5, named `render_invoice_html()`, returning a dict instead of a tuple. Billing job creation sets `render_mode = "HTML"`, `html_content`, and no new PDF payload.

- [ ] **Step 4: Implement Closed snapshot-copy branch**

After loading `previous_job`:

```python
previous_mode = (
    previous_job.get("render_mode") or "PDF"
).strip().upper()

job = frappe.new_doc("BCN Print Job")
job.request_id = request_id
job.document_type = "Sales Order"
job.document_name = sales_order.name
job.printer_name = previous_job.printer_name
job.print_format = previous_job.print_format

if previous_mode == "HTML":
    previous_html = previous_job.get("html_content") or ""
    if not previous_html:
        frappe.throw("Stored HTML cashier snapshot is empty")
    job.render_mode = "HTML"
    job.html_content = previous_html
elif previous_mode == "PDF":
    previous_pdf = previous_job.get("pdf_base64") or ""
    if not previous_pdf:
        frappe.throw("Stored PDF cashier snapshot is empty")
    job.render_mode = "PDF"
    job.pdf_base64 = previous_pdf
else:
    frappe.throw("Stored cashier snapshot has unsupported render mode")
```

Then keep the existing Pending/requested fields and insert. This is the only allowed legacy fallback: a job explicitly stored as PDF remains PDF. Never convert an HTML job to wkhtmltopdf.

- [ ] **Step 5: Run tests and commit**

```powershell
python -m pytest tests\test_ourcity_server_script_contract.py -q
git add server_scripts\mobile\cashier_print_bill.py tests\test_ourcity_server_script_contract.py
git commit -m "feat: preserve cashier reprint snapshot mode"
```

---

### Task 7: Extend `bcn_print_jobs` claim response for dual-mode payloads

**Files:**
- Modify: `tests/test_ourcity_server_script_contract.py`
- Modify: `server_scripts/mobile/print_jobs.py`

**Interfaces:**
- Produces claimed `job` JSON with normalized `render_mode`, `html_content`, and legacy `pdf_base64`.

- [ ] **Step 1: Add failing claim-response assertions**

```python
source = _read(SERVER_SCRIPTS / "print_jobs.py")
assert '"render_mode"' in source
assert '"html_content"' in source
assert 'job.get("render_mode") or "PDF"' in source
assert 'job.get("html_content") or ""' in source
assert 'job.get("pdf_base64") or ""' in source
```

Keep stale Processing timeout, ownership, lock, and attempt-count assertions unchanged.

- [ ] **Step 2: Run and verify RED**

```powershell
python -m pytest tests\test_ourcity_server_script_contract.py -q
```

- [ ] **Step 3: Extend the response only; do not change claim semantics**

Inside the claimed job response, use:

```python
"render_mode": (
    job.get("render_mode") or "PDF"
).strip().upper(),
"html_content": job.get("html_content") or "",
"pdf_base64": job.get("pdf_base64") or "",
```

Do not alter Pending selection, `FOR UPDATE`, stale timeout, printer matching, or Processing transition.

- [ ] **Step 4: Run tests and commit**

```powershell
python -m pytest tests\test_ourcity_server_script_contract.py -q
git add server_scripts\mobile\print_jobs.py tests\test_ourcity_server_script_contract.py
git commit -m "feat: expose cashier HTML print payloads"
```

---

### Task 8: Update source-control documentation for the live data fields and deployment order

**Files:**
- Modify: `docs/server-script-mobile.md`
- Modify: `tests/test_ourcity_server_script_contract.py`

**Interfaces:**
- Documents live configuration required before HTML-producing server scripts are enabled.

- [ ] **Step 1: Add failing documentation assertions**

Require the doc to contain:

```python
assert "render_mode" in source
assert "html_content" in source
assert "Long Text" in source
assert "PDF" in source
assert "HTML" in source
assert "EDGE_PATH" in source
```

- [ ] **Step 2: Run and verify RED**

```powershell
python -m pytest tests\test_ourcity_server_script_contract.py -q
```

- [ ] **Step 3: Document the exact live custom fields**

Add:

```text
BCN Print Job
- render_mode: Select; options PDF / HTML; default PDF
- html_content: Long Text
- pdf_base64: existing field, retained for legacy jobs
```

Document the safe deployment order: fields -> Windows dual-mode client -> `bcn_print_jobs` -> HTML producers -> physical test. State that source mirrors do not deploy live automatically.

- [ ] **Step 4: Run full mobile-repo fast tests**

```powershell
python -m pytest tests -q
```

Expected: all fast tests pass.

- [ ] **Step 5: Commit Task 8**

```powershell
git add docs\server-script-mobile.md tests\test_ourcity_server_script_contract.py
git commit -m "docs: describe cashier HTML print deployment"
```

---

### Task 9: Preflight and deploy live `BCN Print Job` fields safely

**Files:**
- Live OurCity metadata only; no repository file mutation in this task.

**Interfaces:**
- Produces live fields required by the server scripts; existing records remain valid as PDF jobs.

- [ ] **Step 1: Inspect current field metadata before mutation**

Using the Windows `config.json` token, query `DocType/BCN Print Job` and verify whether `render_mode`, `html_content`, and `pdf_base64` exist and whether `pdf_base64` is required. Do not print or log API secrets.

- [ ] **Step 2: Create missing fields only**

In Customize Form or via authenticated `Custom Field` REST calls, create:

```text
DT: BCN Print Job
fieldname: render_mode
label: Render Mode
fieldtype: Select
options: PDF\nHTML
default: PDF
reqd: 0

DT: BCN Print Job
fieldname: html_content
label: HTML Content
fieldtype: Long Text
reqd: 0
```

Do not delete or rename `pdf_base64` and do not modify existing queue rows.

- [ ] **Step 3: Re-read metadata and verify exact field definitions**

Expected: both fields exist; `render_mode` allows `PDF` and `HTML`; old jobs with blank `render_mode` remain interpretable as PDF by code.

---

### Task 10: Deploy the Windows client before enabling HTML-producing server scripts

**Files:**
- Local checkout: `C:\Users\htayoolwin\local_printers_winapp_code`

- [ ] **Step 1: Pull the approved Windows branch and verify config**

```powershell
cd C:\Users\htayoolwin\local_printers_winapp_code
git status
git pull
```

Preserve existing `.venv`, local config backups, and unrelated untracked files. Verify `config.json` contains valid `EDGE_PATH` and `SUMATRA_PDF_PATH` without displaying credentials.

- [ ] **Step 2: Run fresh verification**

```powershell
.\.venv\Scripts\python.exe -m pytest tests -q
.\.venv\Scripts\python.exe -m py_compile cashier_html.py polling_client.py printer_handlers.py socket_app.py
```

Do not claim success unless these commands actually pass in the local environment.

- [ ] **Step 3: Restart only cashier polling**

Stop the existing `socket_app.py` process and start:

```powershell
.\.venv\Scripts\python.exe socket_app.py
```

Keep `queue_worker.py` running separately; do not change its files or behavior.

---

### Task 11: Deploy the three live Server Scripts in safe order

**Files:**
- Live API Server Scripts corresponding to repository mirrors.

- [ ] **Step 1: Deploy `bcn_print_jobs` first**

Copy the reviewed `server_scripts/mobile/print_jobs.py` mirror into the enabled live API Server Script for `bcn_print_jobs`. At this point old PDF producers still work because the Windows client defaults missing/old modes to PDF.

- [ ] **Step 2: Smoke-test one existing PDF-mode job**

Confirm the updated claim endpoint still returns/prints an old PDF job and can reach `Printed` through the existing Sumatra path. Do not proceed if legacy PDF printing regresses.

- [ ] **Step 3: Deploy `bcn_request_for_bill`**

Copy the full reviewed `server_scripts/mobile/request_for_bill.py` into the live API Server Script. Do not paste partial snippets.

- [ ] **Step 4: Deploy `bcn_cashier_print_bill`**

Copy the full reviewed `server_scripts/mobile/cashier_print_bill.py` into the live API Server Script. Do not paste partial snippets.

---

### Task 12: End-to-end physical verification and rollback gate

**Files:**
- No new code unless a reproducible defect is found; any defect starts a new RED test before source changes.

- [ ] **Step 1: Fresh Billing-order automatic print**

Create a brand-new waiter order containing at least one Myanmar item name, then Request for Bill. Verify exactly one new `BCN Print Job` has:

```text
render_mode = HTML
html_content = non-empty
status transitions Pending -> Processing -> Printed
```

Verify physical paper has correct Myanmar shaping and acceptable 80mm top/left/right spacing.

- [ ] **Step 2: Billing reprint**

While the order remains Billing, press Reprint once. Verify exactly one new request/job, fresh HTML snapshot, and exactly one additional physical bill.

- [ ] **Step 3: Complete payment, then Closed reprint**

Pay the existing Draft Sales Invoice, then Reprint the Closed order. Verify the new job copies the previous snapshot mode/content and the paper matches the stored receipt rather than a newly rendered changed document.

- [ ] **Step 4: Legacy PDF compatibility**

Use a known pre-change PDF-mode job or controlled PDF test job. Verify missing/`PDF` `render_mode` still decodes `pdf_base64` and prints through Sumatra.

- [ ] **Step 5: Waiter kitchen regression check**

Submit a new waiter order that routes to a kitchen counter. Verify the existing `queue_worker.py` still creates/prints the kitchen ticket exactly as before; no cashier change should be required for this path.

- [ ] **Step 6: Rollback rule if HTML physical print fails**

If local Edge HTML printing fails after deployment, leave the dual-mode Windows client in place and restore only the live producer Server Scripts (`bcn_request_for_bill` and `bcn_cashier_print_bill`) to the prior reviewed PDF versions. Do not convert existing Pending HTML jobs into PDF; resolve/cancel them explicitly according to operational status.

---

## Final Verification Commands

Windows printer repo:

```powershell
cd C:\Users\htayoolwin\local_printers_winapp_code
.\.venv\Scripts\python.exe -m pytest tests -q
.\.venv\Scripts\python.exe -m py_compile cashier_html.py polling_client.py printer_handlers.py socket_app.py
```

Mobile/server-script mirror repo:

```powershell
cd C:\Users\htayoolwin\bcn-restaurant-mobile
python -m pytest tests -q
git status
```

Success is not complete until fresh automated output passes **and** the physical mobile cashier receipt is confirmed with Myanmar text, 80mm spacing, Billing reprint, Closed snapshot reprint, legacy PDF compatibility, and waiter kitchen regression coverage.