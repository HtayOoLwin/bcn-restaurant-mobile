from pathlib import Path

from bcn_restaurant.domain.roles import build_role_flags


def test_waiter_role_flag_only_enables_waiter_capability():
    flags = build_role_flags(["Waiter"])
    assert flags == {
        "waiter": True,
        "cashier": False,
        "manager": False,
        "can_request_cashier_print": False,
        "can_view_print_status": False,
        "can_retry_print_jobs": False,
    }
    assert "kitchen" not in flags
    assert "cancel_sales_order" not in flags


def test_system_manager_gets_manager_capability():
    flags = build_role_flags(["System Manager"])
    assert flags["manager"] is True
    assert flags["can_retry_print_jobs"] is True


def test_restaurant_manager_gets_print_management_capabilities():
    flags = build_role_flags(["Restaurant Manager"])
    assert flags["manager"] is True
    assert flags["can_view_print_status"] is True
    assert flags["can_retry_print_jobs"] is True


def test_cashier_gets_cashier_print_and_status_capabilities_only():
    flags = build_role_flags(["Cashier"])
    assert flags["can_request_cashier_print"] is True
    assert flags["can_view_print_status"] is True
    assert flags["can_retry_print_jobs"] is False


def test_administrator_gets_all_capabilities():
    flags = build_role_flags(["Administrator"])
    assert all(flags.values())
    assert "kitchen" not in flags
    assert "cancel_sales_order" not in flags


def test_bootstrap_does_not_expose_a_mobile_kitchen_destination():
    bootstrap = (
        Path(__file__).resolve().parents[1] / "bcn_restaurant" / "api" / "bootstrap.py"
    ).read_text()
    assert '"kitchen_counters"' not in bootstrap
