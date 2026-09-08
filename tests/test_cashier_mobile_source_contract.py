from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MOBILE = ROOT / "mobile" / "bcn_restaurant_mobile" / "lib" / "features"


def source(*parts: str) -> str:
    return (MOBILE.joinpath(*parts)).read_text(encoding="utf-8")


def test_waiter_repository_calls_request_for_bill_api():
    text = source("waiter_progress", "data", "waiter_operations_repository.dart")
    assert "requestBill" in text
    assert "bcn_request_for_bill" in text
    assert "sales_order" in text


def test_waiter_progress_has_confirm_before_requesting_bill():
    text = source("waiter_progress", "presentation", "waiter_progress_screen.dart")
    assert "Request for Bill" in text
    assert "Confirm Bill Request" in text
    assert "Confirm & Print" in text
    assert "Once you request the bill, this order will be locked" in text


def test_waiter_models_parse_billing_status_and_tables_can_lock_ordering():
    progress = source("waiter_progress", "domain", "waiter_operation_models.dart")
    tables = source("waiter", "domain", "table_models.dart")
    table_screen = source("waiter", "presentation", "waiter_tables_screen.dart")

    assert "billingStatus" in progress
    assert "billing_status" in progress
    assert "billingStatus" in tables
    assert "billing_status" in tables
    assert "Bill Requested" in table_screen


def test_cashier_models_are_sales_order_centric_and_gate_payment():
    models = source("cashier", "domain", "cashier_models.dart")
    repository = source("cashier", "data", "cashier_repository.dart")
    screen = source("cashier", "presentation", "cashier_screen.dart")

    assert "class CashierBill" in models
    assert "final List<CashierBill> bills" in models
    assert "billingStatus" in models
    assert "canPay" in models
    assert "required String salesOrder" in repository
    assert "required String salesInvoice" in repository
    assert "data.bills" in screen
    assert "bill.canPay" in screen
    assert "Ordering" in screen
    assert "Bill Requested" in screen
