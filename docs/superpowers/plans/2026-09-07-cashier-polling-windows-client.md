# Cashier Polling Windows Client Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend `HtayOoLwin/local_printers_winapp` so cashier bills are claimed from OurCity through token-authenticated HTTP polling, printed through the existing SumatraPDF path, and reported as Printed/Failed without breaking legacy Socket.IO listeners or automatically reprinting timeout-ambiguous jobs.

**Architecture:** Add a focused polling client module rather than expanding `socket_app.py` into mixed responsibilities. The poller sends installed printer names to `bcn_print_jobs`, receives at most one Processing job with `pdf_base64`, prints it once through a reusable single-job function, and retains the terminal result in memory until `bcn_print_job_result` acknowledges it. While a result is unacknowledged, the client retries only the result POST and does not claim or print another job. If the process crashes after paper output, the server eventually marks the old Processing job Failed/unknown and never automatically redelivers it.

**Tech Stack:** Python 3.10+, `requests`, `win32print`, SumatraPDF, existing Socket.IO client, `pytest` + `unittest.mock`.

**Spec:** `docs/superpowers/specs/2026-09-07-cashier-draft-sales-order-billing-design.md` in `HtayOoLwin/bcn-restaurant-mobile`, branch `bcn-restaurant-mobile-without-kitchen-monitor`.

## Global Constraints

- Execution repository is `HtayOoLwin/local_printers_winapp`.
- Do not break existing `document_print_event` or `sales_invoice_submitted` Socket.IO listeners.
- Cashier polling uses `FRAPPE_BASE_URL`, `API_KEY`, `API_SECRET`; it must not depend on login-cookie `AUTH_DATA`.
- Authorization header is exactly `token API_KEY:API_SECRET`.
- Claim endpoint is exactly `/api/method/bcn_print_jobs`.
- Result endpoint is exactly `/api/method/bcn_print_job_result`.
- Every claim sends installed local printer names.
- One poll intentionally claims at most one job.
- `job = null` is normal.
- Default `POLL_INTERVAL_SECONDS` is exactly `2`.
- Physical printing continues through SumatraPDF.
- Success reports `Printed`; print/decode failure reports `Failed` with exact client-side error text.
- Same-terminal result POST may be retried safely after response timeout.
- Result retry must never re-run physical printing.
- While a terminal result is unacknowledged, do not intentionally claim another job.
- Do not implement client-side automatic reprint/reclaim of a timed-out Processing job.
- Server timeout error is `Print result unknown after client timeout`; the cashier decides whether to Reprint.
- Never log API secrets or full Authorization headers.

---

## File Structure

- `polling_client.py` — token auth, claim/result requests, unacknowledged-result state, loop timing.
- `printer_handlers.py` — single-job print function that raises on failure; existing `print_jobs()` compatibility remains.
- `socket_app.py` — starts cashier polling without changing legacy event payload contracts.
- `config copy.json` — documents `FRAPPE_BASE_URL` and `POLL_INTERVAL_SECONDS`.
- `tests/test_polling_client.py` — HTTP contract, sequencing, pending-result retry, null-job, timing.
- `tests/test_printer_handlers.py` — single-job success/failure propagation and legacy compatibility.
- `README.md` — setup and timeout/reprint operations.

---

### Task 1: Make Physical Print Failures Observable

**Files:**
- Modify: `printer_handlers.py`
- Create: `tests/test_printer_handlers.py`

**Interfaces:**
- Consumes: one job `{pdf_base64, printer_name|printer, document_name}` and config `SUMATRA_PDF_PATH`.
- Produces: `print_single_job(job, config_data) -> str`; raises on decode/physical print failure. Existing `print_jobs()` remains callable.

- [ ] **Step 1: Write failing tests**

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
    with patch.object(
        printer_handlers, "save_pdf_from_base64",
        return_value=str(tmp_path / "bill.pdf"),
    ), patch.object(printer_handlers, "print_pdf_silent", return_value=None):
        assert printer_handlers.print_single_job(
            job, {"SUMATRA_PDF_PATH": "SumatraPDF.exe"}
        ) == "Cashier Printer"


def test_print_single_job_propagates_print_failure(tmp_path):
    job = {
        "pdf_base64": "JVBERi0xLjQKJQ==",
        "printer_name": "Cashier Printer",
        "document_name": "SAL-ORD-2026-00005",
    }
    with patch.object(
        printer_handlers, "save_pdf_from_base64",
        return_value=str(tmp_path / "bill.pdf"),
    ), patch.object(
        printer_handlers,
        "print_pdf_silent",
        side_effect=RuntimeError("SumatraPDF returned exit code 1"),
    ):
        with pytest.raises(RuntimeError, match="SumatraPDF returned exit code 1"):
            printer_handlers.print_single_job(
                job, {"SUMATRA_PDF_PATH": "SumatraPDF.exe"}
            )
```

- [ ] **Step 2: Run RED**

```powershell
python -m pytest tests/test_printer_handlers.py -q
```

- [ ] **Step 3: Make low-level print failure raise after logging**

For `subprocess.CalledProcessError`:

```python
raise RuntimeError(
    f"SumatraPDF returned exit code {exc.returncode}"
) from exc
```

For other unexpected exceptions, log then re-raise the original exception.

- [ ] **Step 4: Add `print_single_job`**

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
        "SUMATRA_PDF_PATH",
        r"C:\Program Files\SumatraPDF\SumatraPDF.exe",
    )
    print_pdf_silent(pdf_path, printer_name, sumatra_pdf_path)
    return printer_name
```

Refactor legacy `print_jobs()` to call `print_single_job()` inside its existing loop while keeping existing event handling/logging behavior.

- [ ] **Step 5: Run GREEN**

```powershell
python -m pytest tests/test_printer_handlers.py -q
python -m py_compile printer_handlers.py socket_app.py
```

- [ ] **Step 6: Commit and review in Windows repo**

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
- Consumes: `FRAPPE_BASE_URL/API_KEY/API_SECRET`, installed printer names.
- Produces: `claim_job(session, cfg, printers) -> dict|None`; `report_result(session, cfg, job_name, status, error_message="") -> dict`.

- [ ] **Step 1: Write failing exact HTTP tests**

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

    assert polling_client.claim_job(
        session, _cfg(), ["Cashier Printer"]
    ) is None
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
        "message": {
            "job_name": "JOB-X",
            "status": "Printed",
            "duplicate": False,
        }
    }
    session.post.return_value = response

    result = polling_client.report_result(
        session, _cfg(), "JOB-X", "Printed"
    )
    assert result["status"] == "Printed"
```

- [ ] **Step 2: Run RED**

```powershell
python -m pytest tests/test_polling_client.py -q
```

- [ ] **Step 3: Add URL/auth helpers**

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

Never log the returned header.

- [ ] **Step 4: Implement Frappe envelope parsing and endpoint functions**

```python
def frappe_message(response) -> dict:
    response.raise_for_status()
    payload = response.json()
    message = payload.get("message")
    if not isinstance(message, dict):
        raise ValueError("Frappe API returned an invalid message envelope")
    return message
```

`claim_job` POSTs `{"printers": printers}` and returns `message["job"]`, validating dict-or-None. `report_result` accepts only Printed/Failed and includes `error_message` only for Failed when non-empty.

- [ ] **Step 5: Run GREEN**

```powershell
python -m pytest tests/test_polling_client.py -q
```

- [ ] **Step 6: Commit and review**

```powershell
git add polling_client.py tests/test_polling_client.py
git commit -m "feat: add cashier print queue http client"
```

---

### Task 3: Print Once, Retain Unacknowledged Result, Retry Result Only

**Files:**
- Modify: `polling_client.py`
- Modify: `tests/test_polling_client.py`

**Interfaces:**
- Consumes: `claim_job`, `print_single_job`, `report_result`.
- Produces: `PendingResult`; `process_claimed_job(...) -> PendingResult`; `flush_pending_result(...) -> bool`.

- [ ] **Step 1: Add failing data/sequence tests**

Use:

```python
from dataclasses import dataclass

@dataclass
class PendingResult:
    job_name: str
    status: str
    error_message: str = ""
```

Test successful physical print creates Printed result exactly once:

```python
def test_process_claimed_job_prints_once_and_returns_result():
    job = {
        "name": "JOB-X",
        "printer_name": "Cashier Printer",
        "pdf_base64": "AAA=",
    }
    with patch("polling_client.print_single_job") as print_job:
        result = polling_client.process_claimed_job(job, _cfg())
    print_job.assert_called_once()
    assert result == polling_client.PendingResult("JOB-X", "Printed", "")
```

Test print exception returns Failed result with exact text and does not report inside `process_claimed_job`:

```python
def test_process_claimed_job_captures_exact_failure():
    job = {"name": "JOB-X", "printer_name": "Cashier Printer", "pdf_base64": "AAA="}
    with patch(
        "polling_client.print_single_job",
        side_effect=RuntimeError("SumatraPDF returned exit code 1"),
    ):
        result = polling_client.process_claimed_job(job, _cfg())
    assert result.status == "Failed"
    assert result.error_message == "SumatraPDF returned exit code 1"
```

- [ ] **Step 2: Add failing result-retry test proving no reprint**

Mock first `report_result` call to raise `requests.Timeout`, second to return `duplicate=true`. Call `flush_pending_result` twice or a bounded retry helper. Assert `print_single_job` is never called by result flushing.

- [ ] **Step 3: Run RED**

```powershell
python -m pytest tests/test_polling_client.py -q
```

- [ ] **Step 4: Implement `PendingResult` and `process_claimed_job`**

```python
@dataclass
class PendingResult:
    job_name: str
    status: str
    error_message: str = ""


def process_claimed_job(job: dict, cfg: dict) -> PendingResult:
    job_name = str(job.get("name") or "").strip()
    if not job_name:
        raise ValueError("Claimed print job has no name")
    try:
        print_single_job(job, cfg)
        return PendingResult(job_name, "Printed", "")
    except Exception as exc:
        return PendingResult(job_name, "Failed", str(exc))
```

- [ ] **Step 5: Implement `flush_pending_result`**

```python
def flush_pending_result(session, cfg: dict, pending: PendingResult) -> bool:
    try:
        report_result(
            session,
            cfg,
            pending.job_name,
            pending.status,
            error_message=pending.error_message,
        )
        return True
    except requests.RequestException:
        return False
```

Do not call `claim_job` or `print_single_job` here.

- [ ] **Step 6: Run GREEN**

```powershell
python -m pytest tests/test_polling_client.py -q
```

- [ ] **Step 7: Commit and review**

```powershell
git add polling_client.py tests/test_polling_client.py
git commit -m "feat: retain cashier print result until acknowledged"
```

---

### Task 4: Add Poll Loop That Blocks New Claims While Result Is Pending

**Files:**
- Modify: `polling_client.py`
- Modify: `tests/test_polling_client.py`

**Interfaces:**
- Consumes: installed-printer callback, claim/process/flush functions.
- Produces: `run_polling_loop(cfg, get_printers, stop_requested)`.

- [ ] **Step 1: Add failing null-job/default-interval test**

Patch `time.sleep`; stop after one iteration. When `POLL_INTERVAL_SECONDS` is absent, assert sleep receives `2.0`. `job=None` must not call physical print or result reporting.

- [ ] **Step 2: Add failing pending-result blocking test**

Arrange one claim and successful physical print, then make result reporting fail twice across loop iterations. Assert:

```text
claim_job call count       = 1
print_single_job call count = 1
report_result call count    >= 2
```

No second claim may happen while `PendingResult` remains unacknowledged.

- [ ] **Step 3: Add acknowledgement-unblocks-next-claim test**

First result attempt fails; later attempt succeeds. Only after success may the loop invoke `claim_job` for the next job.

- [ ] **Step 4: Run RED**

```powershell
python -m pytest tests/test_polling_client.py -q
```

- [ ] **Step 5: Implement loop state**

Core structure:

```python
def run_polling_loop(cfg, get_printers, stop_requested):
    session = requests.Session()
    pending_result = None
    interval = _poll_interval(cfg)

    while not stop_requested():
        if pending_result is not None:
            if flush_pending_result(session, cfg, pending_result):
                pending_result = None
            time.sleep(interval)
            continue

        printers = get_printers()
        job = claim_job(session, cfg, printers)
        if job is not None:
            pending_result = process_claimed_job(job, cfg)
            if flush_pending_result(session, cfg, pending_result):
                pending_result = None

        time.sleep(interval)
```

`_poll_interval` converts config to float and returns `2.0` for missing, invalid, or non-positive values.

- [ ] **Step 6: Run GREEN**

```powershell
python -m pytest tests/test_polling_client.py -q
```

- [ ] **Step 7: Commit and review**

```powershell
git add polling_client.py tests/test_polling_client.py
git commit -m "feat: poll cashier queue without duplicate printing"
```

---

### Task 5: Integrate Polling with Current Windows App Without Breaking Socket.IO

**Files:**
- Modify: `socket_app.py`
- Modify: `tests/test_polling_client.py` or create `tests/test_socket_app_polling.py`

**Interfaces:**
- Consumes: current config loader, installed-printer discovery, `run_polling_loop`.
- Produces: cashier polling worker plus unchanged legacy Socket.IO listeners.

- [ ] **Step 1: Add failing integration/source contract test**

Assert `socket_app.py` still contains both legacy event names:

```python
assert "document_print_event" in source
assert "sales_invoice_submitted" in source
assert "run_polling_loop" in source
```

- [ ] **Step 2: Run RED**

```powershell
python -m pytest tests -q
```

- [ ] **Step 3: Start poller as a dedicated daemon thread**

After config loads and before/around Socket.IO blocking wait, start one thread that calls `run_polling_loop`. Use current `get_local_printers()`/`win32print.EnumPrinters` path as the callback. Do not change the legacy Socket.IO event payload parser or `print_jobs()` event handler.

- [ ] **Step 4: Define clean stop behavior**

Use one `threading.Event`. Pass `stop_event.is_set` as `stop_requested`; set event during shutdown/KeyboardInterrupt before disconnecting Socket.IO.

- [ ] **Step 5: Run GREEN + syntax checks**

```powershell
python -m pytest tests -q
python -m py_compile socket_app.py polling_client.py printer_handlers.py
```

- [ ] **Step 6: Commit and review**

```powershell
git add socket_app.py tests
git commit -m "feat: start cashier queue polling alongside socket printing"
```

---

### Task 6: Document Config and Timeout Operations

**Files:**
- Modify: `config copy.json`
- Modify: `README.md`
- Modify: tests if config/source contracts exist.

**Interfaces:**
- Produces: deployable Windows configuration and support instructions.

- [ ] **Step 1: Update sample config**

Include:

```json
{
  "FRAPPE_BASE_URL": "https://ourcity.s.frappe.cloud",
  "API_KEY": "printer-api-key",
  "API_SECRET": "printer-api-secret",
  "POLL_INTERVAL_SECONDS": 2,
  "SUMATRA_PDF_PATH": "C:\\Users\\<user>\\AppData\\Local\\SumatraPDF\\SumatraPDF.exe"
}
```

Retain legacy Socket.IO/login keys already needed by legacy mode; do not remove them solely for cashier polling.

- [ ] **Step 2: Document operational semantics**

README must state:

```text
- Cashier HTTP polling uses API Key/API Secret, not AUTH_DATA cookies.
- Poll interval defaults to 2 seconds.
- A claimed job is physically printed once by the process.
- If result POST cannot be acknowledged, the process retries only the result and does not claim another job.
- If the app crashes after paper output, OurCity eventually marks the Processing job Failed with:
  Print result unknown after client timeout
- The server does not automatically redeliver that job.
- Cashier/operator decides whether to Reprint; a manual reprint may duplicate paper if the first print actually succeeded.
```

- [ ] **Step 3: Run full Windows verification**

```powershell
python -m pytest tests -q
python -m py_compile socket_app.py polling_client.py printer_handlers.py
```

- [ ] **Step 4: Commit and review**

```powershell
git add "config copy.json" README.md tests
git commit -m "docs: document timeout-safe cashier polling"
```

---

## Live Integration Smoke Test

After server/mobile Tasks 3-9 and Windows Tasks 1-6 are reviewed and deployed:

1. Configure dedicated printer API user with Role `BCN Printer Client`.
2. Set DMT exact cashier printer and Sales Order print format.
3. Start Windows client and verify token-auth polling reaches OurCity.
4. Table 01: create waiter order -> SO Open.
5. Cashier Print Bill -> one Pending job and SO Billing.
6. Windows claim -> Processing -> one physical bill -> Printed.
7. Confirm waiter edit is blocked.
8. Pay -> SO Closed/submitted -> SI `update_stock=1` -> PE(s) -> outstanding zero -> table Available.
9. Retry same Print Bill HTTP request id in a controlled test -> same job returned, no second queue job.
10. Failure test: stop/kill the Windows process after a controlled claim without result; after >60 seconds call claim API from a client and verify the old Processing job becomes Failed with exact timeout error and is not returned to Pending.
11. Confirm no automatic paper retry occurs; only a manual Cashier Reprint creates a new Pending job.

Do not merge either repository into its default/main branch as part of this work.
