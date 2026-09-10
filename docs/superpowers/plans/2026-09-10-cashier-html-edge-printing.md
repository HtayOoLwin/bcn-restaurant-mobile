# Cashier HTML + Edge Printing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Print mobile cashier Sales Invoice receipts with correct Myanmar shaping and 80mm spacing by storing HTML snapshots in `BCN Print Job` and rendering them locally with Microsoft Edge, while preserving legacy PDF jobs and waiter kitchen printing.

**Architecture:** New cashier jobs call `frappe.get_print(..., as_pdf=False)` so Frappe stores its browser-style rendered HTML instead of a wkhtmltopdf PDF. `bcn_print_jobs` returns `render_mode`, `html_content`, and legacy `pdf_base64`; the Windows client renders `HTML` mode through Edge and then uses the existing Sumatra print function, while missing/`PDF` mode keeps the old base64-PDF path. Closed-order reprints copy the stored snapshot instead of re-rendering.

**Tech Stack:** ERPNext/Frappe v16 Server Script API, Python 3.10+, Microsoft Edge headless, SumatraPDF, pytest, PowerShell.

**Spec:** `docs/superpowers/specs/2026-09-10-cashier-html-edge-printing-design.md`

## Global Constraints

- Production target: `https://ourcity.s.frappe.cloud`.
- Company: `Doh Myot Daw BBQ & Restaurant`; POS Profile: `DMT`; Currency: `MMK`.
- GitHub Server Script mirrors do not deploy live OurCity automatically.
- Do not change payment logic, order lifecycle semantics, `queue_worker.py`, or waiter kitchen behavior.
- Keep `pdf_base64`; missing `render_mode` means `PDF`.
- New cashier jobs use `render_mode = "HTML"` plus `html_content`.
- Do not silently fall back from HTML mode to wkhtmltopdf when Edge fails.
- Do not add or distribute font files; use Windows/Edge local font support.
- Frappe Server Scripts must avoid sequence unpacking because Safe Exec can raise `_unpack_sequence_`; use dict/index access.
- Use RED-GREEN testing before each behavior change and fresh verification before completion.

---

## File Map

### `HtayOoLwin/local_printers_winapp` — branch `feature/kitchen-print-queue-polling`

- Create `cashier_html.py` — cashier-only UTF-8 Edge renderer.
- Create `tests/test_cashier_html.py` — renderer behavior tests.
- Modify `printer_handlers.py` — dual PDF/HTML dispatch.
- Modify `tests/test_printer_handlers.py` — backward compatibility and HTML dispatch tests.
- Modify `tests/test_polling_client.py` — HTML pass-through/failure contract.
- Modify `README.md`, `tests/test_cashier_polling_docs.py` — deployment/config documentation.
- Leave `queue_worker.py` and `kitchen_ticket.py` unchanged.

### `HtayOoLwin/bcn-restaurant-mobile` — branch `bcn-restaurant-mobile-without-kitchen-monitor`

- Modify `server_scripts/mobile/request_for_bill.py` — first HTML snapshot job.
- Modify `server_scripts/mobile/cashier_print_bill.py` — Billing fresh HTML reprint; Closed snapshot-copy compatibility.
- Modify `server_scripts/mobile/print_jobs.py` — dual-mode claim payload.
- Modify `tests/test_ourcity_server_script_contract.py` and `tests/test_request_for_bill_merge_contract.py` — source contracts.
- Modify `docs/server-script-mobile.md` — live fields/deployment order.

---

### Task 1: Add the cashier Edge renderer

**Files:**
- Create: `cashier_html.py`
- Create: `tests/test_cashier_html.py`

**Interfaces:**
- Produces `render_html_to_pdf_edge(html: str, edge_path: str, timeout_seconds: float = 15.0) -> str`.

- [ ] **Step 1: Write the failing tests**

Create `tests/test_cashier_html.py`:

```python
import subprocess
import threading
import time
from pathlib import Path
from urllib.parse import unquote, urlparse

import pytest

import cashier_html


def test_edge_renderer_preserves_utf8_and_waits_for_pdf(tmp_path, monkeypatch):
    edge = tmp_path / "msedge.exe"
    edge.write_text("edge", encoding="utf-8")
    seen = {}
    writers = []

    def fake_run(command, check):
        html_uri = command[-1]
        parsed = urlparse(html_uri)
        html_path = Path(unquote(parsed.path.lstrip("/")))
        seen["html"] = html_path.read_text(encoding="utf-8")
        pdf_arg = next(x for x in command if x.startswith("--print-to-pdf="))
        pdf_path = Path(pdf_arg.split("=", 1)[1])

        def delayed_write():
            time.sleep(0.08)
            pdf_path.write_bytes(b"%PDF-cashier-edge")

        thread = threading.Thread(target=delayed_write)
        thread.start()
        writers.append(thread)

    monkeypatch.setattr(subprocess, "run", fake_run)
    html = "<html><meta charset='utf-8'><body>မြန်မာ စမ်းသပ်</body></html>"
    pdf_path = cashier_html.render_html_to_pdf_edge(html, str(edge), timeout_seconds=2)

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
            "<html><body>bill</body></html>", str(edge), timeout_seconds=0.05
        )
```

- [ ] **Step 2: Verify RED**

```powershell
cd C:\Users\htayoolwin\local_printers_winapp_code
.\.venv\Scripts\python.exe -m pytest tests\test_cashier_html.py -q
```

Expected: import/collection failure because `cashier_html.py` does not exist.

- [ ] **Step 3: Implement the minimal renderer**

Create `cashier_html.py`:

```python
from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import time
from pathlib import Path


def render_html_to_pdf_edge(html: str, edge_path: str, timeout_seconds: float = 15.0) -> str:
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
    raise RuntimeError("Microsoft Edge did not create the cashier PDF before timeout")
```

- [ ] **Step 4: Verify GREEN and commit**

```powershell
.\.venv\Scripts\python.exe -m pytest tests\test_cashier_html.py -q
git add cashier_html.py tests\test_cashier_html.py
git commit -m "feat: add cashier Edge HTML renderer"
```

---

### Task 2: Make `print_single_job()` dual-mode

**Files:**
- Modify: `printer_handlers.py`
- Modify: `tests/test_printer_handlers.py`

**Interfaces:**
- Missing/`PDF` mode uses `pdf_base64`; `HTML` mode uses `html_content` and `EDGE_PATH`; both end at existing `print_pdf_silent()`.

- [ ] **Step 1: Add failing tests**

Append to `tests/test_printer_handlers.py`:

```python
def test_print_single_job_missing_render_mode_keeps_pdf_path(monkeypatch, tmp_path):
    calls = []
    monkeypatch.setattr(
        printer_handlers,
        "save_pdf_from_base64",
        lambda value: calls.append(("decode", value)) or str(tmp_path / "bill.pdf"),
    )
    monkeypatch.setattr(
        printer_handlers,
        "print_pdf_silent",
        lambda pdf, printer, path, **kwargs: calls.append(
            ("print", pdf, printer, path, kwargs)
        ),
    )
    result = printer_handlers.print_single_job(
        {"pdf_base64": "AAA=", "printer_name": "Kitchen Printer"},
        {"SUMATRA_PDF_PATH": "SumatraPDF.exe"},
    )
    assert result == "Kitchen Printer"
    assert calls[0] == ("decode", "AAA=")
    assert calls[1][0] == "print"


def test_print_single_job_html_mode_renders_then_prints(monkeypatch, tmp_path):
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
        {"EDGE_PATH": "msedge.exe", "SUMATRA_PDF_PATH": "SumatraPDF.exe"},
    )
    assert result == "Kitchen Printer"
    assert calls[0] == ("render", "<html><body>မြန်မာ</body></html>", "msedge.exe")
    assert calls[1][0] == "print"


def test_print_single_job_html_mode_requires_html_content():
    with pytest.raises(ValueError, match="HTML print job has no html_content"):
        printer_handlers.print_single_job(
            {"render_mode": "HTML", "printer_name": "Kitchen Printer"},
            {"EDGE_PATH": "msedge.exe"},
        )


def test_print_single_job_rejects_unknown_render_mode():
    with pytest.raises(ValueError, match="Unsupported print render_mode"):
        printer_handlers.print_single_job(
            {"render_mode": "RAW", "printer_name": "Kitchen Printer"}, {}
        )
```

- [ ] **Step 2: Verify RED**

```powershell
.\.venv\Scripts\python.exe -m pytest tests\test_printer_handlers.py -q
```

Expected: HTML tests fail because current handler requires `pdf_base64`.

- [ ] **Step 3: Implement mode dispatch**

Add:

```python
from cashier_html import render_html_to_pdf_edge
```

Replace the start of `print_single_job()` with:

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

Keep the existing common Sumatra block and `-print-settings "noscale"` unchanged.

- [ ] **Step 4: Verify GREEN/full Windows regression and commit**

```powershell
.\.venv\Scripts\python.exe -m pytest tests\test_printer_handlers.py tests\test_cashier_html.py -q
.\.venv\Scripts\python.exe -m pytest tests -q
git add printer_handlers.py tests\test_printer_handlers.py
git commit -m "feat: print cashier HTML jobs through Edge"
```

---

### Task 3: Lock the polling contract and Windows docs

**Files:**
- Modify: `tests/test_polling_client.py`
- Modify: `README.md`
- Modify: `tests/test_cashier_polling_docs.py`
- `polling_client.py` should remain unchanged if tests pass.

- [ ] **Step 1: Add HTML pass-through/failure tests**

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
    def fail(job, cfg):
        raise RuntimeError("Microsoft Edge did not create the cashier PDF before timeout")
    monkeypatch.setattr(polling_client, "print_single_job", fail)
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

- [ ] **Step 2: Run polling tests**

```powershell
.\.venv\Scripts\python.exe -m pytest tests\test_polling_client.py -q
```

Expected: pass without production change because `process_claimed_job()` already forwards the full job and captures exceptions. If not, stop and debug the exact failing contract before editing production code.

- [ ] **Step 3: Make the documentation test RED, then update README**

Add to `tests/test_cashier_polling_docs.py`:

```python
assert "EDGE_PATH" in cfg
assert "render_mode" in source
assert "HTML" in source
assert "pdf_base64" in source
assert "Microsoft Edge" in source
```

Run:

```powershell
.\.venv\Scripts\python.exe -m pytest tests\test_cashier_polling_docs.py -q
```

Then update README to show both flows explicitly:

```text
HTML: Draft Sales Invoice -> HTML snapshot -> BCN Print Job -> Edge -> local PDF -> Sumatra -> printer
PDF:  pdf_base64 -> local PDF -> Sumatra -> printer
```

State `EDGE_PATH` is required for HTML jobs and `queue_worker.py` remains separate.

- [ ] **Step 4: Verify and commit**

```powershell
.\.venv\Scripts\python.exe -m pytest tests -q
.\.venv\Scripts\python.exe -m py_compile cashier_html.py polling_client.py printer_handlers.py socket_app.py
git add tests\test_polling_client.py README.md tests\test_cashier_polling_docs.py
git commit -m "test: cover dual-mode cashier polling"
```

---

### Task 4: Convert Request for Bill to an HTML snapshot

**Files:**
- Modify: `tests/test_ourcity_server_script_contract.py`
- Modify: `tests/test_request_for_bill_merge_contract.py`
- Modify: `server_scripts/mobile/request_for_bill.py`

**Interfaces:**
- New initial job keeps deterministic `bill-request|<Sales Order>` idempotency and stores `render_mode = HTML`, `html_content`, and the selected Sales Invoice Print Format.

- [ ] **Step 1: Make source-contract tests RED**

Change Request-for-Bill assertions to:

```python
assert "render_sales_invoice_html" in source
assert "as_pdf=False" in source
assert 'job.render_mode = "HTML"' in source
assert 'job.html_content = rendered["html_content"]' in source
assert 'request_id = "bill-request|" + sales_order.name' in source
assert "encode_pdf_base64" not in source
assert "as_pdf=True" not in source
```

Keep existing SO submit, Draft SI creation, `update_stock = 1`, Pending, duplicate, and no explicit commit/rollback assertions.

Run:

```powershell
cd C:\Users\htayoolwin\bcn-restaurant-mobile
python -m pytest tests\test_ourcity_server_script_contract.py tests\test_request_for_bill_merge_contract.py -q
```

Expected: RED against current PDF implementation.

- [ ] **Step 2: Implement Safe-Exec-friendly HTML rendering**

Replace the PDF encoder/helper with:

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
        frappe.throw("Cashier Sales Invoice print format not found: " + invoice_print_format)
    if print_format_row.disabled:
        frappe.throw("Cashier Sales Invoice print format is disabled: " + invoice_print_format)
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
    return {"html_content": html_content, "print_format": invoice_print_format}
```

Inside `ensure_print_job()` use dict access only:

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

Remove PDF base64 generation from new Request-for-Bill jobs.

- [ ] **Step 3: Verify GREEN and commit**

```powershell
python -m pytest tests\test_ourcity_server_script_contract.py tests\test_request_for_bill_merge_contract.py -q
git add server_scripts\mobile\request_for_bill.py tests\test_ourcity_server_script_contract.py tests\test_request_for_bill_merge_contract.py
git commit -m "feat: queue cashier bill HTML snapshots"
```

---

### Task 5: Make cashier reprint snapshot-compatible

**Files:**
- Modify: `tests/test_ourcity_server_script_contract.py`
- Modify: `server_scripts/mobile/cashier_print_bill.py`

- [ ] **Step 1: Add RED assertions**

```python
assert "render_invoice_html" in source
assert "as_pdf=False" in source
assert 'job.render_mode = "HTML"' in source
assert "job.html_content" in source
assert 'previous_job.get("render_mode") or "PDF"' in source
assert 'if previous_mode == "HTML":' in source
assert "previous_job.get(\"html_content\")" in source
assert "previous_job.get(\"pdf_base64\")" in source
assert 'job.render_mode = "PDF"' in source
```

Run `python -m pytest tests\test_ourcity_server_script_contract.py -q` and confirm failure.

- [ ] **Step 2: Implement Billing fresh HTML render**

Use the same Print Format validation as Task 4, named `render_invoice_html()`, returning a dict and calling `frappe.get_print(..., as_pdf=False)`. Billing reprint sets `render_mode = "HTML"` and `html_content`.

- [ ] **Step 3: Implement Closed snapshot copy exactly**

```python
previous_mode = (previous_job.get("render_mode") or "PDF").strip().upper()
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

Keep the existing request-id lock/idempotency and Pending fields unchanged.

- [ ] **Step 4: Verify and commit**

```powershell
python -m pytest tests\test_ourcity_server_script_contract.py -q
git add server_scripts\mobile\cashier_print_bill.py tests\test_ourcity_server_script_contract.py
git commit -m "feat: preserve cashier reprint snapshot mode"
```

---

### Task 6: Extend the print-job claim response

**Files:**
- Modify: `tests/test_ourcity_server_script_contract.py`
- Modify: `server_scripts/mobile/print_jobs.py`

- [ ] **Step 1: Add RED assertions**

```python
assert '"render_mode"' in source
assert '"html_content"' in source
assert 'job.get("render_mode") or "PDF"' in source
assert 'job.get("html_content") or ""' in source
assert 'job.get("pdf_base64") or ""' in source
```

Run `python -m pytest tests\test_ourcity_server_script_contract.py -q` and confirm failure.

- [ ] **Step 2: Add payload fields without changing claim semantics**

Inside the claimed job response add:

```python
"render_mode": (job.get("render_mode") or "PDF").strip().upper(),
"html_content": job.get("html_content") or "",
"pdf_base64": job.get("pdf_base64") or "",
```

Do not change Pending selection, printer matching, `FOR UPDATE`, stale timeout, Processing transition, or attempt counting.

- [ ] **Step 3: Verify and commit**

```powershell
python -m pytest tests\test_ourcity_server_script_contract.py -q
git add server_scripts\mobile\print_jobs.py tests\test_ourcity_server_script_contract.py
git commit -m "feat: expose cashier HTML print payloads"
```

---

### Task 7: Document and create the live fields, then deploy in safe order

**Files:**
- Modify: `docs/server-script-mobile.md`
- Modify: `tests/test_ourcity_server_script_contract.py`
- Live OurCity metadata and Server Scripts.

- [ ] **Step 1: Make documentation contract RED**

Require `docs/server-script-mobile.md` to contain `render_mode`, `html_content`, `Long Text`, `PDF`, `HTML`, and `EDGE_PATH`; run the contract test and confirm RED.

- [ ] **Step 2: Document exact live metadata**

```text
BCN Print Job
- render_mode: Select; options PDF / HTML; default PDF; not required
- html_content: Long Text; not required
- pdf_base64: existing field retained for legacy jobs
```

Document deployment order: fields -> Windows dual-mode client -> `bcn_print_jobs` -> `bcn_request_for_bill` -> `bcn_cashier_print_bill` -> physical tests.

- [ ] **Step 3: Verify mobile-repo tests and commit docs**

```powershell
python -m pytest tests -q
git add docs\server-script-mobile.md tests\test_ourcity_server_script_contract.py
git commit -m "docs: describe cashier HTML print deployment"
```

- [ ] **Step 4: Create the live fields without touching existing data**

Use Customize Form or authenticated Custom Field REST creation. Create only missing fields with the exact definitions above. Do not delete/rename `pdf_base64`; do not rewrite existing queue rows.

- [ ] **Step 5: Deploy Windows first and verify it**

```powershell
cd C:\Users\htayoolwin\local_printers_winapp_code
git status
git pull
.\.venv\Scripts\python.exe -m pytest tests -q
.\.venv\Scripts\python.exe -m py_compile cashier_html.py polling_client.py printer_handlers.py socket_app.py
```

Preserve `.venv`, local config backups, and unrelated untracked files. Restart `socket_app.py`; keep `queue_worker.py` running separately.

- [ ] **Step 6: Deploy live Server Scripts in this order**

1. Replace live `bcn_print_jobs` with the full reviewed mirror; smoke-test one legacy PDF job.
2. Replace live `bcn_request_for_bill` with the full reviewed mirror.
3. Replace live `bcn_cashier_print_bill` with the full reviewed mirror.

Never paste partial snippets into live Server Scripts.

---

### Task 8: Physical E2E verification and rollback gate

**Files:** none unless a reproducible defect is found; any defect requires a new failing test before source edits.

- [ ] **Step 1: Fresh automatic bill**

Create a brand-new waiter order containing at least one Myanmar item name, Request for Bill, and verify exactly one new job with:

```text
render_mode = HTML
html_content = non-empty
Pending -> Processing -> Printed
```

Verify physical Myanmar shaping and 80mm top/left/right spacing.

- [ ] **Step 2: Billing reprint**

Press Reprint once while Billing. Verify one new request/job and exactly one additional physical bill.

- [ ] **Step 3: Closed reprint**

Complete payment, then Reprint the Closed order. Verify the new job copies the stored snapshot mode/content rather than re-rendering changed invoice state.

- [ ] **Step 4: Legacy PDF regression**

Verify an old/missing-`render_mode` PDF job still decodes `pdf_base64` and prints through Sumatra.

- [ ] **Step 5: Waiter kitchen regression**

Submit a new waiter order routed to a kitchen counter and verify the existing `queue_worker.py` ticket flow still prints unchanged.

- [ ] **Step 6: Rollback rule**

If HTML physical printing fails, keep the dual-mode Windows client and restore only the live producer scripts `bcn_request_for_bill` and `bcn_cashier_print_bill` to their prior reviewed PDF versions. Do not silently convert Pending HTML jobs to PDF; resolve them explicitly.

## Final Verification

Windows repo:

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

Completion requires fresh automated pass output plus physical confirmation of Myanmar text, 80mm spacing, Billing reprint, Closed snapshot reprint, legacy PDF compatibility, and waiter kitchen regression.