# Cashier HTML + Edge Printing Design

Date: 2026-09-10

## Context

Cashier Sales Invoice printing currently renders a PDF on the Frappe/ERPNext server using `frappe.get_print(..., as_pdf=True)`, stores the base64 PDF in `BCN Print Job`, and lets the Windows printer client decode and print the PDF through SumatraPDF.

Manual printing from the ERPNext browser is visually correct, including Myanmar text and receipt spacing. The mobile cashier path is not correct because the server-generated PDF uses wkhtmltopdf. On the live OurCity site, `DMT Cashier Invoice` only permits `wkhtmltopdf`; attempting to set `pdf_generator = chrome` returns a ValidationError. The wkhtmltopdf output has incorrect Myanmar shaping and receipt sizing/margins.

## Goal

Preserve the existing cashier workflow while replacing server-side cashier PDF rendering with an HTML snapshot rendered locally on Windows by Microsoft Edge. This should make the mobile cashier receipt match the browser rendering more closely, especially for Myanmar text and 80mm thermal receipt sizing.

## Non-goals

- Do not change waiter kitchen ticket behavior.
- Do not remove existing PDF printing support.
- Do not change payment logic.
- Do not change restaurant order lifecycle semantics.
- Do not silently fall back from HTML mode to wkhtmltopdf if local Edge rendering fails.

## Data model changes

Add two fields to `BCN Print Job`:

1. `html_content`
   - Type: Long Text
   - Stores the rendered cashier HTML snapshot.

2. `render_mode`
   - Type: Select
   - Options:
     - PDF
     - HTML
   - Default: PDF

Keep the existing `pdf_base64` field unchanged for backward compatibility.

## Cashier print flow

New cashier jobs use this flow:

1. Waiter requests the bill or cashier requests a reprint.
2. ERPNext creates or finds the relevant Draft Sales Invoice.
3. Server renders `DMT Cashier Invoice` as HTML rather than as PDF.
4. Server stores the rendered HTML in `BCN Print Job.html_content` and sets `render_mode = HTML`.
5. Windows poller claims the job.
6. Windows printer client writes the HTML to a UTF-8 local file.
7. Microsoft Edge headless renders the HTML to a local PDF.
8. The local PDF is printed through the existing SumatraPDF print path.
9. The client reports Printed or Failed to the server.

Existing PDF jobs keep the original path:

`pdf_base64 -> temporary PDF -> SumatraPDF -> printer`

## Server-side HTML rendering

Use Frappe's existing printview HTML rendering path rather than `frappe.get_print(..., as_pdf=True)` for HTML-mode cashier jobs. The target print format remains the POS Profile field `custom_cashier_invoice_print_format`.

The stored HTML must be a snapshot of the bill at the time the print job is created so later document changes do not mutate historical reprints.

## Reprint rules

### Billing order

A fresh reprint request for a Billing order renders the current linked Draft Sales Invoice to fresh HTML and creates a new print job.

### Closed order

A Closed order reprint copies the latest stored printable snapshot rather than re-rendering from the current document. For an HTML-origin job, copy `render_mode = HTML` and `html_content`. For an older PDF-origin job, copy `render_mode = PDF` and `pdf_base64`.

This preserves receipt consistency across reprints.

## Windows rendering

Reuse the proven local Edge rendering approach already used by the kitchen ticket flow. The Windows renderer must:

- write UTF-8 HTML,
- use Microsoft Edge headless mode,
- disable Edge PDF header/footer,
- wait until a non-empty PDF is actually written,
- fail clearly if Edge does not create a PDF within the timeout.

Cashier-specific print CSS must enforce an 80mm thermal receipt layout with zero or minimal margins and must not depend on Frappe Cloud's wkhtmltopdf font environment.

Myanmar text is rendered by local Windows/Edge fonts. No font files are bundled or distributed by this change.

## Windows job dispatch

`printer_handlers.print_single_job()` becomes dual-mode:

- `render_mode = PDF` or missing: existing base64 PDF behavior.
- `render_mode = HTML`: render `html_content` with Edge, then send the resulting PDF through the existing SumatraPDF path.

If an HTML job has no `html_content`, fail the job. Do not fall back to `pdf_base64` unless the job itself is explicitly PDF mode.

## Server polling contract

`bcn_print_jobs` adds these fields to each claimed job response:

- `render_mode`
- `html_content`
- existing `pdf_base64`

The client remains backward compatible with old jobs where `render_mode` is missing by treating them as PDF jobs.

## Files expected to change

### bcn-restaurant-mobile repository

- `server_scripts/mobile/request_for_bill.py`
- `server_scripts/mobile/cashier_print_bill.py`
- `server_scripts/mobile/print_jobs.py`
- relevant server-script contract tests

### local_printers_winapp repository

- `polling_client.py` only if claim/result tests require new payload expectations
- `printer_handlers.py`
- a cashier HTML/Edge rendering helper, or a safe shared helper extracted from the kitchen renderer
- relevant Windows unit tests

`queue_worker.py` must remain unchanged.

## Deployment order

1. Add `html_content` and `render_mode` fields to `BCN Print Job`.
2. Deploy the Windows client update first so it understands both PDF and HTML jobs.
3. Update `bcn_print_jobs` to return the new fields.
4. Update `bcn_request_for_bill` and `bcn_cashier_print_bill` to create HTML-mode jobs.
5. Run a fresh Billing-order physical print test.
6. Verify Closed-order reprint snapshot behavior.
7. Verify an old PDF-mode job still prints.

GitHub mirror updates do not deploy live OurCity Server Scripts automatically; live Server Scripts must be updated separately.

## Failure and rollback behavior

HTML jobs must fail visibly when Edge rendering fails. The client reports the error to `bcn_print_job_result` and must not silently print a wkhtmltopdf fallback.

Rollback is performed by switching cashier job creation back to PDF mode. Because the Windows client remains dual-mode, no rollback of the Windows client is required for PDF compatibility.

Pending HTML jobs must not be silently converted to PDF during rollback.

## Testing strategy

Use test-first development for behavior changes.

Required automated coverage:

1. HTML-mode claimed job contains `render_mode` and `html_content`.
2. Old/missing `render_mode` continues through PDF path.
3. HTML job rejects missing `html_content`.
4. Edge renderer waits for a non-empty PDF.
5. Edge failure is reported as Failed.
6. Closed-order reprint preserves the stored snapshot mode/content.
7. PDF-mode reprint preserves existing behavior.
8. Waiter kitchen queue flow is unaffected by the changed files.

Required manual verification:

1. Fresh Billing order creates exactly one cashier HTML job.
2. Myanmar item names render correctly on the physical 80mm receipt.
3. Left/right/top spacing is acceptable on the physical printer.
4. Fresh cashier Reprint creates one additional physical copy.
5. Closed-order Reprint matches the stored receipt snapshot.
6. Existing PDF-mode job still prints through SumatraPDF.

## Success criteria

The mobile cashier receipt prints through the existing Windows printer client with correct Myanmar rendering and 80mm receipt spacing, while preserving existing PDF print compatibility, reprint consistency, and waiter kitchen printing behavior.
