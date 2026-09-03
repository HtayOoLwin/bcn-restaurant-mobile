# Item-Group Windows Print Routing Design

**Date:** 2026-09-03  
**Repository:** `HtayOoLwin/bcn-restaurant-mobile`  
**Branch:** `bcn-restaurant-mobile-without-kitchen-monitor`

## Objective

Replace the kitchen-monitor workflow with reliable server-managed printing. Kitchen tickets are created automatically when a Sales Order is submitted, split by Item Group, and delivered to mapped Windows printers through the Local Printers Windows middleware. Cashier bills are printed only when the cashier presses **Print Bill**.

## Scope

### Included

- Remove Kitchen Monitor navigation and user-facing flows from the Flutter app.
- Route submitted Sales Order items to kitchen printers by Item Group.
- Send unmapped items to one default kitchen printer per POS Profile.
- Print a cancellation ticket when an authorized ERPNext user cancels a Sales Order.
- Prevent Waiter users from cancelling Sales Orders.
- Route cashier bills to a configured Windows printer on manual request.
- Persist print jobs, acknowledgements, retry counts, and errors.
- Retry failed delivery/printing up to three times and allow manual retry.
- Prevent duplicate kitchen and cancellation tickets.
- Replace the mobile Bluetooth printer setup with Windows printing status and controls.

### Excluded

- Android Bluetooth or direct network printing.
- A Kitchen Monitor screen or kitchen order status workflow.
- Automatic cashier printing after payment.
- Waiter cancellation.
- Changes unrelated to order and printing behavior.

## System Architecture

ERPNext is the source of truth and print-job coordinator. The Windows middleware is the execution agent.

1. The Flutter app submits an order through the existing ERPNext API.
2. The Sales Order `on_submit` event groups items by configured printer.
3. ERPNext renders one filtered kitchen ticket per destination printer.
4. ERPNext persists each job before publishing a Socket.IO notification.
5. The Windows middleware receives the notification, claims the job, prints it using the exact Windows printer name, and acknowledges success or failure.
6. ERPNext records the result. Unacknowledged or failed jobs remain retryable.
7. When the middleware reconnects, it requests pending jobs so jobs published while it was offline are not lost.

Cashier printing follows the same durable job mechanism, but starts only from the mobile **Print Bill** action.

## Printer Configuration

Continue using the existing Local Printers doctypes and extend `Printer Item Group`.

| Field | Purpose |
|---|---|
| POS Profile | Isolates printer settings by restaurant/POS configuration |
| Target DocType | `Sales Order` for kitchen tickets; `Sales Invoice` for cashier bills |
| Trigger Method | `on_submit`, `on_cancel`, or `manual` |
| Printer | Exact printer name reported by the Windows machine |
| Printer IP | Optional metadata; Windows printer name remains authoritative |
| Print Format | Server-side Frappe print format |
| Printer Item Groups | Item Groups routed to this printer |
| Is Cashier | Marks the full-document cashier destination |
| Is Default Kitchen | Receives otherwise-unmapped Sales Order items |
| Enabled | Excludes disabled mappings |

Validation rules:

- Only one enabled default kitchen printer is allowed for each POS Profile.
- A cashier configuration uses `Sales Invoice`, `manual`, and `Is Cashier`.
- Kitchen configurations use `Sales Order` and are not cashier configurations.
- Printer names must match names synchronized by the Windows middleware.
- If no default kitchen printer exists, unmapped items are logged and the user is warned; Sales Order submission is not blocked.

## Item Routing

For each Sales Order item, ERPNext reads the Item's exact `item_group`.

- If one or more enabled configurations contain that Item Group, the row is included in each matching printer's ticket.
- If there is no match, the row goes to the default kitchen printer.
- Items are grouped by destination printer, so one Sales Order produces at most one kitchen job per printer.
- Cashier bills are not filtered; the cashier printer receives the complete Sales Invoice.

Routing uses the committed Sales Order document, not client-provided printer names, to prevent tampering and configuration drift.

## Durable Print Job

Add a `Local Print Job` DocType owned by the Local Printers integration.

| Field | Description |
|---|---|
| Job ID | Unique idempotency key |
| Document Type | Sales Order or Sales Invoice |
| Document Name | Source document name |
| POS Profile | Configuration scope |
| Ticket Type | Kitchen, Cancel, or Cashier |
| Printer | Exact Windows printer name |
| Print Format | Format used to render the payload |
| Status | Pending, Sent, Printing, Success, or Failed |
| Attempt Count | Number of claimed print attempts |
| Error Message | Latest failure detail |
| Payload | Rendered PDF or durable payload reference |
| Created At | Job creation timestamp |
| Printed At | Successful acknowledgement timestamp |
| Requested By | User who triggered a manual cashier print/retry |

### Idempotency

Kitchen and cancellation jobs use a deterministic key composed of source DocType, document name, printer, and event. A successful job with the same key is never recreated or automatically reprinted.

Each cashier button press is an intentional print/reprint and receives a new Job ID. The UI labels later requests as reprints when the bill has already printed successfully.

## Events

### Sales Order Submit

- Trigger: `Sales Order.on_submit`.
- Build routes from Item Group configuration.
- Create and publish one Kitchen job per printer.
- Do not fail the Sales Order transaction because a printer is offline.

### Sales Order Cancel

- Trigger: `Sales Order.on_cancel`.
- Only ERPNext users with Cancel permission can cancel.
- Create one Cancel job for every printer that received the original kitchen order.
- Use the original successful/persisted routing records rather than recalculating from current Item master configuration.

### Cashier Print Bill

- Trigger: explicit authenticated API request from the Flutter cashier screen.
- Validate Cashier permission and the requested Sales Invoice.
- Create one manual Cashier job using the enabled cashier configuration.
- Return the created job status to the app; printing does not depend on the Android device remaining connected.

## Ticket Content

### Kitchen Ticket

- KITCHEN TICKET
- Table/customer name
- Sales Order number
- Order date and time
- Waiter name
- NEW ORDER indicator
- Item quantity
- Item name
- Item note/remark
- No rate, amount, tax, or total

### Cancel Ticket

- Prominent bold CANCEL ORDER heading
- Table/customer name
- Sales Order number
- Cancellation date and time
- Cancelling user
- Original routed item quantity, name, and note/remark

### Cashier Bill

Continue using the existing cashier bill information, layout, and receipt footer, rendered through its configured Frappe Print Format and sent to the Windows cashier printer.

## Retry and Acknowledgement

- Publishing a Socket.IO event is a notification, not proof of printing.
- Middleware claims a Pending job before printing and acknowledges Success or Failed afterward.
- A job may be attempted at most three times automatically.
- After three failed attempts, it remains Failed until an authorized manual retry.
- Manual retry resets it to Pending without changing its idempotency key.
- On reconnection, middleware fetches Pending jobs and eligible Failed/Sent jobs whose acknowledgement timed out.
- Job claiming must be atomic so two middleware instances cannot print the same job concurrently.
- A stale Printing job returns to retryable state after a defined acknowledgement timeout.

## Mobile App Changes

Remove or disconnect:

- `/kitchen` route and Kitchen Monitor screen access.
- Kitchen navigation icons and notification badges.
- Kitchen-first authentication redirects.
- Kitchen queue monitoring and kitchen status actions.
- Waiter-facing cancellation actions.
- Bluetooth discovery, pairing, connection, and direct print services.
- Bluetooth printer packages and Android permissions when no remaining feature uses them.

Retain waiter progress/ready screens only if they serve a non-kitchen-monitor business flow; otherwise remove their routes, navigation, providers, and unused API dependencies after reference analysis.

Change Printer Settings into a Windows Print Service screen showing:

- Middleware online/offline or last-seen state.
- Pending and Failed job counts.
- Manual **Retry Failed Jobs** action for authorized users.
- **Test Cashier Print** action.

Change Cashier **Print Bill** to call the new server API instead of `CashierPrinterService.printBill`.

## Permissions

- Waiter: submit orders; cannot cancel Sales Orders or manually retry jobs.
- Cashier: request cashier bill printing and view relevant print result.
- Restaurant Manager/System Manager: cancel Sales Orders, view all print jobs, retry failures, and maintain printer mappings.
- Windows middleware user: read/claim assigned pending jobs and acknowledge results; no broader document write permission.

Both UI visibility and server-side API permission checks are required.

## Failure Behavior

- Missing Item Group mapping: route to the default kitchen printer.
- Missing default printer: log unmapped items and show a warning without blocking submission.
- Windows middleware offline: retain Pending jobs.
- Printer unavailable/paper error: record failure, retry up to three times, then require manual retry.
- Socket.IO delivery loss: middleware recovery query finds persisted pending work.
- Duplicate event delivery: deterministic Job ID prevents duplicate kitchen/cancel jobs.
- Partial printer failure: successful jobs stay Success; only unsuccessful destinations retry.
- Cashier request without configuration: return a clear error and create no incomplete job.

## Required Repository Changes

### `bcn-restaurant-mobile`

- Update Frappe Sales Order event hooks and printing APIs.
- Add server APIs for cashier print, job polling/claim, acknowledgement, status, retry, and test print.
- Update Flutter router, authentication redirects, navigation, cashier action, and printer-status screen.
- Remove unused Kitchen Monitor and direct-print dependencies after reference checks.
- Add backend and Flutter tests for permissions and user-facing behavior.

### `local_printers`

- Extend printer configuration fields and validation.
- Add durable Local Print Job persistence.
- Add item routing, default fallback, cancellation routing history, idempotency, retry, claim, and acknowledgement.
- Update Windows middleware to claim persisted jobs and acknowledge outcomes.
- Retain Socket.IO as a low-latency notification channel, with polling/recovery after reconnect.

Changes spanning the two repositories must use compatible versioned payloads so either side can report an unsupported version clearly.

## Testing

### Backend

- Exact Item Group routing and multi-printer splitting.
- Default-printer fallback and missing-default warning.
- One deterministic job per order/printer/event.
- Original-route cancellation tickets.
- Waiter cancellation rejection.
- Cashier print permission and manual-only trigger.
- Atomic claim behavior.
- Success/failure acknowledgement and retry limit.
- Reconnection recovery and stale-claim recovery.

### Flutter

- No Kitchen Monitor route, icon, badge, or redirect.
- Waiter cannot see cancellation actions.
- Cashier Print Bill calls the server job API and displays accepted/error states.
- Windows print status screen reflects pending/failed/offline states.
- No Android Bluetooth permission is requested after dependency removal.

### Windows Middleware

- Correct printer selection by exact Windows name.
- Successful acknowledgement after the spool call succeeds.
- Failure acknowledgement with useful error detail.
- Automatic retry does not exceed three attempts.
- Reconnection obtains missed pending jobs.
- Duplicate Socket.IO notification does not print an already-successful job.

## Deployment Order

1. Deploy Local Printers backend schema and APIs.
2. Configure printers, Item Groups, default kitchen printer, and print formats in a test POS Profile.
3. Upgrade Windows middleware and verify claim/acknowledgement with a test job.
4. Deploy the Frappe restaurant hooks/APIs.
5. Deploy the Flutter build with Kitchen Monitor and Bluetooth paths removed.
6. Execute end-to-end tests for kitchen, fallback, cancel, retry, and cashier printing.
7. Enable production printer mappings.
