# OurCity V2 — Room Charges & Draft Billing Flow

Target source branch: `our-city-restaurant-mobile-V2`.
This feature branch is staging only. **Do not deploy until all APIs and Flutter screens are migrated together.**

## Business rules (approved)
1. No table transfers. Each table/customer has one active restaurant Sales Order at a time.
2. First successful new Sales Order creation saves server-side `custom_check_in` once. Later orders never change it.
3. All Sales Orders, even those without a room-charge item, store `custom_check_in` and most-recent `custom_check_out`.
4. Waiter selects room charge as an item. Only items flagged `Item.custom_is_room_charge=1` activate billing by duration. A room-charge item may be added late; duration still starts at initial check-in.
5. Request for Bill updates `custom_check_out` to server time. Charge by full first hour, then round any remaining portion up in 30-minute blocks. Formula in seconds: `billable_half_hours = max(2, ceil(elapsed_seconds / 1800))`; `qty = billable_half_hours / 2`.
6. Room charge row is a non-stock sales item with UOM Hour, rate resolved from the selected Item Price and then frozen to the applicable SO item rate. System owns its quantity. Allow at most one room-charge item row per SO (including variants); waiter cannot manually edit its charge quantity or overwrite rate.
7. Request for Bill keeps SO at docstatus=0, restaurant_status=Billing; re-requests update the **same** SO row and save it. They create immutable, versioned bill-print snapshots. Prior bill snapshots must not be used for payment.
8. Additional food/drink orders allowed until Cashier Pay; any order changes set status back to Open or flag bill outdated. Require fresh Request for Bill before Pay. The room charge row must never route to the kitchen.
9. Cashier Pay (separate API action) validates latest bill, locks the SO, submits SO and creates one linked draft SI. Status = Payment Pending. Must be idempotent.
10. Confirm Payment (separate API action) submits SI, creates allocated Payment Entries and closes SO only if outstanding is zero. Payment attempts need idempotency/retry handling.
11. No room-charge item: do not add a charge; all other states and check-in/out timestamps behave the same.
12. Server timestamps only; lock SO row for concurrent mutations. Use one transaction, no explicit commit on failure.
13. On submitted SO, no waiter additions or new room-charge recalculations.

## Required ERPNext setup (before deployment)
- `Sales Order.custom_check_in`: Datetime, read-only
- `Sales Order.custom_check_out`: Datetime, read-only
- `Sales Order.custom_duration`: Float (elapsed hours, not rounded), read-only
- `Sales Order.custom_billable_hours`: Float, read-only
- `Sales Order.custom_bill_revision`: Int, default 0 (increases on each bill reprint)
- `Sales Order.custom_billed_revision`: Int (only latest generated print revision)
- `Item.custom_is_room_charge`: Check, default 0
- Room charge Item: non-stock, sales item, Hour UOM, matching Item Price for configured selling price list. Allow just one flagged item row per order.
- If `Payment Pending` is a Select field, add that option to `custom_restaurant_status` before deployment.
- Printer snapshot/version reference must be stored on BCN Print Job; add a dedicated revision field or use unique `request_id` `bill-request|<SO>|<revision>`.

## API migration checklist
- `server_scripts/mobile/create_order.py`: stamp check-in at insert; accept docstatus 0 Open or Billing, invalidate bill on any added item; validate and protect room item; never change check-in.
- `server_scripts/mobile/request_for_bill.py`: remove SO submit/SI generation; stamp checkout, compute duration/room qty, update SO, increment bill revision; print draft SO preview using explicit print format, never stale SI snapshot.
- `server_scripts/mobile/cashier_billing.py`: list draft Billing SO; action `Pay` only locks/submits SO and creates Draft SI; action `ConfirmPayment` handles tender allocations, submits SI and creates PE; guard repeated actions.
- `server_scripts/mobile/cashier_print_bill.py`: reprint latest version with consistent document state, not outdated snapshots.
- `server_scripts/mobile/waiter_order_progress.py`, `server_scripts/mobile/tables.py`: map updated states and active orders.
- Flutter Waiter menu/table/progress: check-in/checkout display from server, no local room timer; allow orders after Billing and show bill-invalidated prompt.
- Flutter Cashier: separate Pay (invoice draft) and Confirm Payment (tenders), handle Payment Pending.
- Printing workers: skip room service rows in kitchen printing; cashier bill renders latest room line and time detail.

## Verification matrix
| Scenario | Expected |
|---|---|
| Normal table without flagged item | timestamps saved, no room fee |
| Room item from first order | first hour min; ceil next 30m |
| Room item added after 1h | first SO check-in determines duration |
| 1h15 elapsed | 1.5 hours |
| 1h42 elapsed | 2 hours |
| Request bill twice | same SO/item row, current checkout and latest print |
| Add food after bill | SO draft remains editable, old bill invalid |
| Print retry | no double charge/duplicate print mutation |
| Cashier Pay twice | one submitted SO and one Draft SI |
| Confirm Payment twice | one set of payments, SI submitted once |
| Invalid payment / SI validation failure | no partial closes or extra payment |
| Room item removed | no room fee on revised bill |
| Concurrent waiter/cashier operations | serialized, cannot edit submitted SO |

## Deployment safety
Current repository server scripts are copied to the Frappe site manually and are not necessarily active there. No production deployment is done by merely updating this GitHub feature branch. Full integration/UAT required before activation.
