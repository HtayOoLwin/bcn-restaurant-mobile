# Credit Customers (OurCity Restaurant V2)

## Flutter implementation
The Cashier app bar has a **Credit Customers** action at `/cashier/credits`.
The new screen loads outstanding credit customers, then submitted unpaid Sales Invoices,
and opens a payment dialog for partial/full settlement. It refreshes after success.

## Required ERPNext staging deployment
The Flutter screens require the authenticated Server Script API endpoints:
- `bcn_get_credit_customers`
- `bcn_get_customer_credit_details`
- `bcn_receive_credit_payment`

They must be deployed and validated on `ourcity-testing.s.frappe.cloud`
before testing the UI. If they do not exist, the UI shows an API error, not fake balances.

### Accounting expectations
- Company: Doh Myot Daw BBQ & Restaurant; currency: MMK.
- Credit checkout submits a Sales Invoice *without* applying a full payment.
- The submitted invoice remains outstanding.
- Sales Invoice custom checkbox `custom_restaurant_credit` = 1 for credit checkout invoices.
- Payment Entry has a unique Data field `custom_restaurant_request_id`.
- Payment Entry Type = Receive; Party Type = Customer, Party = invoice customer.
- `paid_from` = the invoice receivable account, `paid_to` = approved Cash/Bank account.
- A Payment Entry Reference allocates to the submitted Sales Invoice.
- API validates role, company, invoice ownership, positive payment, available outstanding,
  mode-of-payment account and duplicate request ID before posting.
- Only submitted invoice outstanding is displayed; no separate mutable customer credit balance.

### Payment retries
The dialog creates a request ID once when opened, reusing it for retries in the
same dialog. The server must enforce uniqueness and prevent concurrent payments
that exceed outstanding balances. An unknown network result needs an ERPNext
status check prior to retry, especially if the dialog has been closed.

### Configuration
Mode options in the initial UI are Cash, Bank and KBZPay. Align these names
with ERPNext Mode of Payment records and approved MMK accounts.
The UI is **not** evidence that a Payment Entry was created until the API
returns success. Do not enable for production until server-side concurrency,
permission and idempotency tests pass.

### Manual test plan
1. Credit checkout of MMK 100,000 creates a submitted invoice with 100,000 outstanding.
2. Cashier opens Credit Customers and sees the customer and invoice.
3. Receive MMK 40,000; the server submits one Payment Entry allocated to the invoice.
4. Refresh shows MMK 60,000 outstanding; pay the remainder to see it disappear.
5. Reject zero/negative/overpayment and unapproved Cash/Bank modes.
6. Retry one request ID: exactly one Payment Entry.
7. Concurrent requests against the same invoice must not overallocate.
8. Cancel an eligible Payment Entry; outstanding reflects the cancellation.
