"""Source-level regression checks for room charge checkout migration.

These checks verify the implementation contract without requiring an ERPNext site.
Real billing, printing and payment flows still require integration/UAT tests.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SERVER = ROOT / "server_scripts" / "mobile"
MOBILE = ROOT / "mobile" / "bcn_restaurant_mobile" / "lib"


def billable_hours(elapsed_seconds: float) -> float:
    half_hours = max(2, int((elapsed_seconds + 1799.999999) // 1800))
    return half_hours / 2.0


def test_minimum_one_hour_and_half_hour_round_up():
    assert billable_hours(0) == 1
    assert billable_hours(3600) == 1
    assert billable_hours(3601) == 1.5
    assert billable_hours(4500) == 1.5
    assert billable_hours(5400) == 1.5
    assert billable_hours(5401) == 2
    assert billable_hours(7800) == 2.5


def test_checkout_freezes_once_before_any_payment_preparation():
    server = (SERVER / "cashier_billing.py").read_text(encoding="utf-8")
    start = server.split('elif action == "StartCheckout":', 1)[1].split('elif action == "Pay":', 1)[0]
    payment = server.split('elif action == "Pay":', 1)[1].split('elif action == "ConfirmPayment":', 1)[0]
    assert 'SELECT name FROM `tabSales Order` WHERE name=%(name)s FOR UPDATE' in start
    assert 'so.custom_check_out = now' in start
    assert 'so.custom_restaurant_status = "Billing"' in start
    assert 'so.get("custom_check_out") or frappe.utils.now_datetime()' in start
    assert 'if state != "Billing" or not so.get("custom_check_out")' in payment
    assert 'so.custom_check_out = now' not in payment


def test_cashier_pay_and_credit_share_start_checkout_before_credit_picker():
    cashier = (MOBILE / "features" / "cashier" / "presentation" / "cashier_screen.dart").read_text(encoding="utf-8")
    method = cashier.split("Future<void> _prepareAndOpenPayment(", 1)[1].split("Future<void> _openPaymentSheet(", 1)[0]
    start = method.index(".startCheckout(bill.salesOrder)")
    picker = method.index("_chooseCreditCustomer(context)")
    prepare = method.index(".preparePayment(bill.salesOrder")
    assert start < picker < prepare


def test_preview_is_read_only_and_calculates_tax_and_room_total():
    server = (SERVER / "waiter_order_progress.py").read_text(encoding="utf-8")
    assert "preview_doc.calculate_taxes_and_totals()" in server
    assert '"room_preview": room_preview' in server
    assert '"is_live": bool(' in server
    assert "preview_doc.save(" not in server
    assert "frappe.db.set_value(" not in server
