# BCN Restaurant Mobile Phase 2 Waiter + Kitchen Design

## Goal
Add production-oriented Waiter progress/serve actions and Kitchen preparation queues to the existing BCN Restaurant custom app and Flutter client while preserving Sales Order as the KOT transaction.

## Scope
Phase 2 adds:
- kitchen queue isolated by the logged-in user's Kitchen Counter User Permissions
- kitchen state transitions: New -> Accepted -> Preparing -> Ready
- waiter order progress for the logged-in waiter's active table sessions
- waiter ready-to-serve queue
- waiter item actions: Mark Served, Cancel New item
- waiter whole-order action: Serve Whole Order only when every active line is Ready or Served
- parent Sales Order preparation summary recalculation
- in-app waiter Notification Log when a kitchen line becomes Ready
- Flutter role routing for Kitchen users and Waiter progress/ready screens
- polling refresh for Phase 2; realtime remains deferred

## Operational Boundary
Only Sales Orders linked to Restaurant Table Session records in Open or Billing status are considered active mobile restaurant orders. This intentionally prevents old unbilled test Sales Orders from appearing in mobile queues.

Kitchen queues include both Dine In and Takeaway because preparation routing is counter-based. Waiter progress is limited to sessions whose `waiter` is the current user, except Administrator/System Manager who may see all active sessions.

## State Machine
Kitchen:
- New + Accept -> Accepted
- Accepted + Start Preparation -> Preparing
- Preparing + Mark Ready -> Ready

Waiter:
- Ready + Mark Served -> Served
- New + Cancel -> Cancelled, only when no submitted Sales Invoice Item or Delivery Note Item exists for that Sales Order Item
- Serve Whole Order -> all remaining Ready rows become Served; action is blocked while any active row is New, Accepted, or Preparing

Cancelled rows are excluded from active-line counts.

## Parent Summary
For active rows only:
- all Served -> Served
- all Ready/Served -> Ready to Serve
- any Ready/Served -> Partially Ready
- any Accepted/Preparing -> Preparing
- otherwise -> New

`custom_ready_count` stores the number of Ready lines, not quantity. `custom_total_prep_lines` stores active line count.

## Backend Components
- `bcn_restaurant/domain/preparation.py`: pure transition/summary rules
- `bcn_restaurant/services/preparation.py`: Frappe persistence/recalculation helpers
- `bcn_restaurant/api/kitchen.py`: queue + item transition endpoint
- `bcn_restaurant/api/waiter.py`: progress, ready queue, waiter actions

State-changing endpoints use POST; list endpoints use GET. Mobile never writes Sales Order Item directly.

## Security
- Kitchen endpoint requires Kitchen role (System Manager/Administrator bypass through shared role helper).
- Allowed counters come from User Permission records for Kitchen Counter. Administrator can access all enabled counters.
- Every item mutation reloads the parent Sales Order and confirms it belongs to the configured restaurant company, is submitted, and belongs to an active Restaurant Table Session.
- Waiter mutation confirms the session belongs to the current waiter unless the caller is Administrator/System Manager.

## Flutter UX
### Kitchen
- After login, Kitchen-only users land on Kitchen Orders.
- Header shows assigned counters.
- Tabs/filters: All, New, Accepted, Preparing, Ready.
- Each line shows table/takeaway, item, qty/UOM, kitchen note, elapsed time, counter, status.
- One context-valid primary action is shown per line.
- Pull-to-refresh plus 10-second polling while screen is visible.

### Waiter
- Table screen adds Ready and Progress actions.
- Ready screen groups Ready lines by Sales Order/table and offers Mark Served / Serve Whole Order.
- Progress screen shows each current active order with New, Preparing, Ready, Served counts and item details.
- New items may be cancelled from Progress with confirmation.
- Pull-to-refresh plus 10-second polling on operational screens.

## Error Handling
Invalid or stale transitions fail server-side with a clear Frappe validation message. After any successful mutation the Flutter provider refreshes from the server rather than assuming local state.

## Testing
Pure transition and summary rules are covered with pytest first. API contract tests assert whitelisted endpoint presence and POST decorators for mutations. Flutter model/controller tests are added for kitchen action mapping and waiter progress parsing; Flutter analyze/test is run only where Flutter SDK exists.

## Deferred
- Socket.IO realtime
- cashier consolidated billing/payment
- Delivery Note auto-submit
- manager exceptions/dashboard
- shift open/close DocType
