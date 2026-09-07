# Cashier Polling Windows Client Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend `HtayOoLwin/local_printers_winapp` so cashier bills are claimed from OurCity through token-authenticated HTTP polling, printed through the existing SumatraPDF path, and reported as Printed/Failed without breaking legacy Socket.IO listeners.

**Architecture:** Add a focused polling client module rather than turning `socket_app.py` into a larger mixed-responsibility file. The poller sends installed printer names to `bcn_print_jobs`, receives at most one Processing job with `pdf_base64`, prints it through a reusable single-job function, posts the terminal result to `bcn_print_job_result`, then polls again after the configured interval. Existing Socket.IO behavior remains available for unrelated legacy/kitchen events.

**Tech Stack:** Python 3.10+, `requests`, `win32print`, SumatraPDF, existing Socket.IO client, `pytest`/`unittest.mock` style unit tests.

**Spec:** `docs/superpowers/specs/2026-09-07-cashier-draft-sales-order-billing-design.md` in orchestration repository `HtayOoLwin/bcn-restaurant-mobile`, branch `bcn-restaurant-mobile-without-kitchen-monitor`.

## Global Constraints

- Execution repository is `HtayOoLwin/local_printers_winapp`.
- Do not break existing `document_print_event` or `sales_invoice_submitted` Socket.IO listeners.
- Cashier polling uses `FRAPPE_BASE_URL`, `API_KEY`, and `API_SECRET`; it must not depend on login-cookie `AUTH_DATA`.
- Authorization header is exactly `token API_KEY:API_SECRET`.
- Claim endpoint is exactly `/api/method/bcn_print_jobs`.
- Result endpoint is exactly `/api/method/bcn_print_job_result`.
- Every claim sends installed local printer names.
- One poll intentionally claims at most one job.
- `job = null` is normal and not an error.
- Default `POLL_INTERVAL_SECONDS` is exactly `2`.
- The current job result must be reported before intentionally claiming another job.
- Success reports `Printed`; failures report `Failed` with the exact client-side error text.
- Same-terminal result POST may be retried safely after response timeout.
- Physical printing continues through SumatraPDF.
- Never store or log API secrets in plaintext logs beyond their existing config file presence.

---

## File Structure

- `polling_client.py` — HTTP token auth, claim/result requests, one polling iteration, loop timing.
- `printer_handlers.py` — expose a single-job function that raises on decode/print failure; keep existing `print_jobs()` compatibility for Socket.IO.
- `socket_app.py` — start cashier polling alongside/around legacy Socket.IO mode without changing legacy event contracts.
- `config copy.json` — document `FRAPPE_BASE_URL` and `POLL_INTERVAL_SECONDS`.
- `tests/test_polling_client.py` — exact HTTP contract, sequencing, null-job handling, timeout/result behavior.
- `tests/test_printer_handlers.py` — single-job success/failure propagation while preserving existing batch behavior.
- `README.md` — polling configuration and operations.

---

### Task 1: Make Physical Print Failures Observable to the Poller

**Files:**
- Modify: `printer_handlers.py`
- Create: `tests/test_printer_handlers.py`

**Interfaces:**
- Consumes: one job dict `{pdf_base64, printer_name|printer, print_format, document_name}` and config `SUMATRA_PDF_PATH`.
- Produces: `print_single_job(job, config_data) -> str` returning printer name on success and raising an exception with the real error on failure; existing `print_jobs()` remains callable for Socket.IO.

- [ ] **Step 1: Write failing unit tests**

```python
from unittest.mock import patch
import pytest

import printer_handlers


def test_print_single_job_returns_printer_on_success(tmp_path):
    job = {
        "pdf_base64": "JVBERi0xLjQKJQ==",
        "printer_name": "Cashier Printer",
        "document_name": "SAL-ORD-2026-00005",
    }
    with patch.object(printer_handlers, "save_pdf_from_base64", return_value=str(tmp_path / "bill.pdf")), \
         patch.object(printer_handlers, "print_pdf_silent", return_value=None):
        assert printer_handlers.print_single_job(job, {"SUMATRA_PDF_PATH": "SumatraPDF.exe"}) == "Cashier Printer"


def test_print_single_job_propagates_print_failure(tmp_path):
    job = {
        "pdf_base64": "JVBERi0xLjQKJQ==",
        "printer_name": "Cashier Printer",
        "document_name": "SAL-ORD-2026-00005",
    }
    with patch.object(printer_handlers, "save_pdf_from_base64", return_value=str(tmp_path / "bill.pdf")), \
         patch.object(printer_handlers, "print_pdf_silent", side_effect=RuntimeError("SumatraPDF returned exit code 1")):
        with pytest.raises(RuntimeError, match="SumatraPDF returned exit code 1"):
            printer_handlers.print_single_job(job, {"SUMATRA_PDF_PATH": "SumatraPDF.exe"})
```

- [ ] **Step 2: Run RED**

```powershell
python -m pytest tests/test_printer_handlers.py -q
```

Expected: FAIL because `print_single_job` does not exist and current `print_pdf_silent` swallows failures.

- [ ] **Step 3: Make `print_pdf_silent` raise after logging**

Keep logging/console output, but change exception handlers so they re-raise. For `subprocess.CalledProcessError`, raise:

```python
raise RuntimeError(f"SumatraPDF returned exit code {exc.returncode}") from exc
```

For unexpected exceptions, re-raise the original exception after logging.

- [ ] **Step 4: Add `print_single_job`**

Implement exact key compatibility:

```python
def print_single_job(job: dict, config_data: dict) -> str:
    pdf_base64 = job.get("pdf_base64")
    printer_name = job.get("printer_name") or job.get("printer")
    if not pdf_base64:
        raise ValueError("Print job has no pdf_base64")
    if not printer_name:
        raise ValueError("Print job has no printer name")

    pdf_path = save_pdf_from_base64(pdf_base64)
    if not pdf_path:
        raise ValueError("Failed to decode/save print job PDF")

    sumatra_pdf_path = config_data.get(
        "SUMATRA_PDF_PATH", r"C:\Program Files\SumatraPDF\SumatraPDF.exe"
    )
    print_pdf_silent(pdf_path, printer_name, sumatra_pdf_path)
    return printer_name
```

Refactor `print_jobs()` to call `print_single_job()` inside its loop while preserving legacy list behavior and logging.

- [ ] **Step 5: Run GREEN + basic legacy tests**

```powershell
python -m pytest tests/test_printer_handlers.py -q
python -m py_compile printer_handlers.py socket_app.py
```

Expected: PASS.

- [ ] **Step 6: Commit in `local_printers_winapp` feature branch**

```powershell
git add printer_handlers.py tests/test_printer_handlers.py
git commit -m "refactor: expose single cashier pdf print result"
```

---

### Task 2: Implement Token-Authenticated Claim and Result HTTP Client

**Files:**
- Create: `polling_client.py`
- Create: `tests/test_polling_client.py`

**Interfaces:**
- Consumes: config `FRAPPE_BASE_URL/API_KEY/API_SECRET`, local printer names.
- Produces: `claim_job(session, cfg, printers) -> dict|None`; `report_result(session, cfg, job_name, status, error_message="") -> dict`.

- [ ] **Step 1: Write failing exact HTTP contract tests**

```python
from unittest.mock import Mock
import polling_client


def _cfg():
    return {
        "FRAPPE_BASE_URL": "https://ourcity.s.frappe.cloud",
        "API_KEY": "key",
        "API_SECRET": "secret",
        "POLL_INTERVAL_SECONDS": 2,
    }


def test_claim_job_posts_exact_contract():
    session = Mock()
    response = Mock()
    response.raise_for_status.return_value = None
    response.json.return_value = {"message": {"job": None}}
    session.post.return_value = response

    assert polling_client.claim_job(session, _cfg(), ["Cashier Printer"]) is None
    session.post.assert_called_once_with(
        "https://ourcity.s.frappe.cloud/api/method/bcn_print_jobs",
        json={"printers": ["Cashier Printer"]},
        headers={"Authorization": "token key:secret"},
        timeout=30,
    )


def test_report_result_posts_exact_contract():
    session = Mock()
    response = Mock()
    response.raise_for_status.return_value = None
    response.json.return_value = {
        "message": {"job_name": "JOB-X", "status": "Printed", "duplicate": False}
    }
    session.post.return_value = response

    result = polling_client.report_result(session, _cfg(), "JOB-X", "Printed")
    assert result["status"] == "Printed"
    session.post.assert_called_once_with(
        "https://ourcity.s.frappe.cloud/api/method/bcn_print_job_result",
        json={"job_name": "JOB-X", "status": "Printed"},
        headers={"Authorization": "token key:secret"},
        timeout=30,
    )
```

- [ ] **Step 2: Run RED**

```powershell
python -m pytest tests/test_polling_client.py -q
```

Expected: FAIL because module does not exist.

- [ ] **Step 3: Implement base URL and auth helpers**

```python
def build_api_url(cfg: dict, method: str) -> str:
    base = str(cfg.get("FRAPPE_BASE_URL") or "").strip().rstrip("/")
    if not base:
        raise ValueError("FRAPPE_BASE_URL is required for cashier polling")
    return f"{base}/api/method/{method}"


def auth_headers(cfg: dict) -> dict[str, str]:
    key = str(cfg.get("API_KEY") or "").strip()
    secret = str(cfg.get("API_SECRET") or "").strip()
    if not key or not secret:
        raise ValueError("API_KEY and API_SECRET are required for cashier polling")
    return {"Authorization": f"token {key}:{secret}"}
```

Never log `secret` or the complete Authorization header.

- [ ] **Step 4: Implement Frappe message-envelope handling**

Create:

```python
def frappe_message(response) -> dict:
    response.raise_for_status()
    payload = response.json()
    message = payload.get("message")
    if not isinstance(message, dict):
        raise ValueError("Frappe API returned an invalid message envelope")
    return message
```

`claim_job` returns `message["job"]`, validating dict-or-None. `report_result` accepts only Printed/Failed and includes `error_message` only for Failed/non-empty error.

- [ ] **Step 5: Run GREEN**

```powershell
python -m pytest tests/test_polling_client.py -q
```

Expected: PASS.

- [ ] **Step 6: Commit**

```powershell
git add polling_client.py tests/test_polling_client.py
git commit -m "feat: add cashier print queue http client"
```

---

### Task 3: Implement One-Job Polling Iteration and Result Sequencing

**Files:**
- Modify: `polling_client.py`
- Modify: `tests/test_polling_client.py`

**Interfaces:**
- Consumes: `claim_job`, `report_result`, `print_single_job`, `get_local_printers` supplied as dependency/callback.
- Produces: `poll_once(...)` that never intentionally claims a second job before reporting the current result.

- [ ] **Step 1: Add failing null-job and success sequencing tests**

```python
def test_poll_once_does_nothing_when_no_job():
    session = Mock()
    with patch("polling_client.claim_job", return_value=None) as claim, \
         patch("polling_client.print_single_job") as print_job, \
         patch("polling_client.report_result") as report:
        polling_client.poll_once(session, _cfg(), ["Cashier Printer"])
        claim.assert_called_once()
        print_job.assert_not_called()
        report.assert_not_called()


def test_poll_once_prints_then_reports_printed():
    events = []
    job = {"name": "JOB-X", "printer_name": "Cashier Printer", "pdf_base64": "AAA="}
    with patch("polling_client.claim_job", side_effect=lambda *a: events.append("claim") or job), \
         patch("polling_client.print_single_job", side_effect=lambda *a: events.append("print") or "Cashier Printer"), \
         patch("polling_client.report_result", side_effect=lambda *a, **k: events.append("report") or {"status": "Printed"}):
        polling_client.poll_once(Mock(), _cfg(), ["Cashier Printer"])
    assert events == ["claim", "print", "report"]
```

- [ ] **Step 2: Add failing failure-result test**

When `print_single_job` raises `RuntimeError("SumatraPDF returned exit code 1")`, assert `report_result(..., "Failed", error_message="SumatraPDF returned exit code 1")` is called and the error text is exact.

- [ ] **Step 3: Run RED**

```powershell
python -m pytest tests/test_polling_client.py -q
```

Expected: FAIL because `poll_once` does not exist.

- [ ] **Step 4: Implement `poll_once`**

```python
def poll_once(session, cfg: dict, printers: list[str]) -> None:
    job = claim_job(session, cfg, printers)
    if job is None:
        return

    job_name = str(job.get("name") or "").strip()
    if not job_name:
        raise ValueError("Claimed print job has no name")

    try:
        print_single_job(job, cfg)
    except Exception as exc:
        report_result(session, cfg, job_name, "Failed", error_message=str(exc))
        return

    report_result(session, cfg, job_name, "Printed")
```

Import `print_single_job` from `printer_handlers`.

- [ ] **Step 5: Add result-response timeout retry helper**

Implement `report_result_with_retry(..., max_attempts=2)`. It retries only transport exceptions from `requests.RequestException`; because server same-terminal result is idempotent, a committed-but-lost response is safe. Use this helper inside `poll_once` for both Printed and Failed reports. Do not reprint when only result reporting timed out.

- [ ] **Step 6: Add retry test**

Mock first result POST to raise `requests.Timeout`, second to return `duplicate=true`; assert printer function ran once and result POST twice.

- [ ] **Step 7: Run GREEN**

```powershell
python -m pytest tests/test_polling_client.py -q
```

Expected: PASS.

- [ ] **Step 8: Commit**

```powershell
git add polling_client.py tests/test_polling_client.py
git commit -m "feat: process cashier print queue one job at a time"
```

---

### Task 4: Add Poll Loop with Configured 2-Second Default

**Files:**
- Modify: `polling_client.py`
- Modify: `tests/test_polling_client.py`

**Interfaces:**
- Consumes: `poll_once`, local printer callback, stop event/callback for testability.
- Produces: `run_polling_loop(cfg, get_printers, stop_requested)`.

- [ ] **Step 1: Add failing interval test**

Use patched `time.sleep` and a stop callback that becomes true after one iteration. Assert default sleep argument is `2.0` when config omits `POLL_INTERVAL_SECONDS`.

- [ ] **Step 2: Add failing config override test**

With `POLL_INTERVAL_SECONDS=5`, assert sleep uses `5.0`. Clamp invalid/non-positive values back to `2.0`.

- [ ] **Step 3: Run RED**

```powershell
python -m pytest tests/test_polling_client.py -q
```

Expected: FAIL because loop does not exist.

- [ ] **Step 4: Implement loop**

Create one `requests.Session()` for reuse. Each iteration re-reads installed printer names via callback, calls `poll_once`, catches/logs request-level errors without leaking credentials, sleeps interval, and exits when `stop_requested()` is true.

- [ ] **Step 5: Run GREEN**

```powershell
python -m pytest tests/test_polling_client.py -q
```

Expected: PASS.

- [ ] **Step 6: Commit**

```powershell
git add polling_client.py tests/test_polling_client.py
git commit -m "feat: poll cashier print queue on configured interval"
```

---

### Task 5: Integrate Poller Without Breaking Legacy Socket.IO

**Files:**
- Modify: `socket_app.py`
- Modify: `tests/test_polling_client.py` or create `tests/test_socket_app_integration.py`

**Interfaces:**
- Consumes: current `load_config`, `get_local_printers`, legacy `run_socketio_client`; new `run_polling_loop`.
- Produces: startup runs cashier polling in a daemon thread while existing Socket.IO client remains the foreground legacy listener.

- [ ] **Step 1: Write failing startup wiring test**

Patch `threading.Thread` (or imported `Thread`) and `run_socketio_client`. Assert startup constructs polling thread with target `run_polling_loop`, passes config and `get_local_printers`, starts it, then calls existing Socket.IO connection path.

- [ ] **Step 2: Run RED**

```powershell
python -m pytest tests/test_socket_app_integration.py -q
```

Expected: FAIL before integration exists.

- [ ] **Step 3: Add a small callable entrypoint instead of testing `__main__` directly**

Refactor startup into:

```python
def run_app(cfg: dict[str, Any]) -> None:
    namespace = str(cfg.get("FRAPPE_SOCKET_URL") or "").strip().rstrip("/")
    register_handlers(namespace)
    polling_thread = Thread(
        target=run_polling_loop,
        args=(cfg, get_local_printers, lambda: False),
        daemon=True,
        name="cashier-print-poller",
    )
    polling_thread.start()
    run_socketio_client(cfg, namespace)
```

Keep current event registrations (`document_print_event`, `sales_invoice_submitted`) unchanged.

- [ ] **Step 4: Make polling optional only through explicit config if needed for rollout**

Default is enabled. If adding `CASHIER_POLLING_ENABLED`, default it to true and document it; do not make polling silently off when key is absent.

- [ ] **Step 5: Run GREEN + compile**

```powershell
python -m pytest -q
python -m py_compile socket_app.py polling_client.py printer_handlers.py
```

Expected: all tests PASS.

- [ ] **Step 6: Commit**

```powershell
git add socket_app.py tests/test_socket_app_integration.py
git commit -m "feat: run cashier polling beside legacy socket printing"
```

---

### Task 6: Update Config Template and Operations Documentation

**Files:**
- Modify: `config copy.json`
- Modify: `README.md`
- Modify: tests if config parsing is covered.

**Interfaces:**
- Consumes: implemented polling settings.
- Produces: deployable Windows configuration instructions.

- [ ] **Step 1: Update sample config to include exact keys**

```json
{
  "FRAPPE_BASE_URL": "https://ourcity.s.frappe.cloud",
  "FRAPPE_SOCKET_URL": "https://your-site.com",
  "LOGIN_URL": "https://your-site.com/api/method/login",
  "AUTH_DATA": {
    "usr": "legacy-socket-user",
    "pwd": "legacy-socket-password"
  },
  "API_KEY": "printer-api-key",
  "API_SECRET": "printer-api-secret",
  "POLL_INTERVAL_SECONDS": 2,
  "SUMATRA_PDF_PATH": "C:\\Program Files\\SumatraPDF\\SumatraPDF.exe"
}
```

Keep legacy Socket.IO fields because unrelated event printing still exists.

- [ ] **Step 2: Update README architecture**

Document two coexistence paths separately: legacy Socket.IO events and cashier HTTP polling. State that cashier polling uses token auth and does not require login cookies.

- [ ] **Step 3: Run full verification**

```powershell
python -m pytest -q
python -m py_compile socket_app.py polling_client.py printer_handlers.py
```

Expected: PASS.

- [ ] **Step 4: Commit**

```powershell
git add "config copy.json" README.md
git commit -m "docs: configure cashier print queue polling"
```

---

### Task 7: End-to-End Live Smoke Test Against OurCity

**Files:** none required unless defects are found.

**Interfaces:**
- Consumes: deployed OurCity queue aliases from the server/mobile plan, configured dedicated API user, exact DMT printer name, running Windows client.
- Produces: verified Pending -> Processing -> Printed path and failure/reprint behavior.

- [ ] **Step 1: Start Windows client**

```powershell
python socket_app.py
```

Expected logs show local printers and cashier polling active without printing API credentials.

- [ ] **Step 2: From restaurant mobile Cashier, Print Bill for controlled Open Sales Order**

Expected sequence in ERPNext:

```text
Sales Order Open -> Billing
BCN Print Job Pending -> Processing -> Printed
```

Expected physical result: one cashier receipt prints to the configured exact Windows printer.

- [ ] **Step 3: Verify waiter lock and payment independence**

Attempt waiter append while Billing: rejected. Complete payment even if print job is temporarily Pending/Failed: payment is allowed and finalizes SO/SI/PE.

- [ ] **Step 4: Verify failure/reprint**

Temporarily make printer unavailable for a controlled test job; confirm Failed with exact error. Restore printer and use Reprint Bill; confirm a new Pending job is created and older Failed job remains unchanged.

- [ ] **Step 5: Verify response-timeout safety at unit level, not by destructive network manipulation**

Rely on Task 3 automated test for committed-result/lost-response retry semantics. Do not intentionally kill production networking during restaurant operations.

- [ ] **Step 6: Record final evidence**

Capture Sales Order, Sales Invoice, Payment Entry(s), print job names/statuses, and Windows log timestamps in the implementation review report. Do not merge any branch as part of this plan.
